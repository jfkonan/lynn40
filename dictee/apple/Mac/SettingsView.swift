import AppKit
import Combine
import SwiftUI

/// Réglages de l'app Mac : clé API, transcription, nettoyage, raccourci, comportement, autorisations.
struct SettingsView: View {
    @ObservedObject var controller: DictationController

    // Réglages communs (SPEC §3), mêmes clés que sur iOS.
    @AppStorage(SharedStore.Key.model, store: SharedStore.shared.defaults)
    private var model = SharedStore.Default.model
    @AppStorage(SharedStore.Key.language, store: SharedStore.shared.defaults)
    private var language = SharedStore.Default.language
    @AppStorage(SharedStore.Key.vocabulary, store: SharedStore.shared.defaults)
    private var vocabulary = SharedStore.Default.vocabulary
    @AppStorage(SharedStore.Key.cleanupEnabled, store: SharedStore.shared.defaults)
    private var cleanupEnabled = SharedStore.Default.cleanupEnabled
    @AppStorage(SharedStore.Key.cleanupModel, store: SharedStore.shared.defaults)
    private var cleanupModel = SharedStore.Default.cleanupModel

    // Réglages propres au Mac.
    @AppStorage(MacSettings.Key.hotkey, store: SharedStore.shared.defaults)
    private var hotkey: HotkeyChoice = MacSettings.Default.hotkey
    @AppStorage(MacSettings.Key.hotkeyMode, store: SharedStore.shared.defaults)
    private var hotkeyMode: HotkeyMode = MacSettings.Default.hotkeyMode
    @AppStorage(MacSettings.Key.soundsEnabled, store: SharedStore.shared.defaults)
    private var soundsEnabled = MacSettings.Default.soundsEnabled
    @AppStorage(MacSettings.Key.restoreClipboard, store: SharedStore.shared.defaults)
    private var restoreClipboard = MacSettings.Default.restoreClipboard
    @AppStorage(MacSettings.Key.launchAtLogin, store: SharedStore.shared.defaults)
    private var launchAtLogin = MacSettings.Default.launchAtLogin

    @State private var apiKeyInput = ""
    @State private var savedKeyPreview: String?
    @State private var keyMessage: String?
    @State private var loginMessage: String?
    @State private var microphoneStatus = Permissions.microphone

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let transcriptionModels = ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]

    var body: some View {
        Form {
            apiKeySection
            shortcutSection
            transcriptionSection
            cleanupSection
            behaviorSection
            permissionsSection
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 700)
        .onAppear {
            savedKeyPreview = KeychainStore.preview(of: KeychainStore.loadAPIKey())
            launchAtLogin = LoginItem.isEnabled
            refreshPermissions()
        }
        .onReceive(permissionTimer) { _ in refreshPermissions() }
        // Le mode compte aussi : il change la consigne du menu (« maintenez » / « appuyez sur »).
        .onChange(of: hotkey) { _ in controller.hotkeySettingsChanged() }
        .onChange(of: hotkeyMode) { _ in controller.hotkeySettingsChanged() }
        .onChange(of: launchAtLogin) { newValue in applyLaunchAtLogin(newValue) }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        Section {
            if let preview = savedKeyPreview {
                LabeledContent("Clé enregistrée") {
                    HStack {
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                        Button("Supprimer", role: .destructive) {
                            KeychainStore.deleteAPIKey()
                            savedKeyPreview = nil
                        }
                    }
                }
            }
            SecureField(savedKeyPreview == nil ? "Clé API" : "Nouvelle clé", text: $apiKeyInput, prompt: Text("sk-…"))
                .onSubmit(saveKey)
            HStack {
                Spacer()
                Button("Enregistrer la clé", action: saveKey)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let keyMessage {
                Text(keyMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        } header: {
            Text("Clé API OpenAI")
        } footer: {
            Text("Stockée dans le Trousseau de ce Mac. Elle n'est envoyée qu'à OpenAI.")
        }
    }

    private var shortcutSection: some View {
        Section {
            Picker("Raccourci", selection: $hotkey) {
                ForEach(HotkeyChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            Picker("Mode", selection: $hotkeyMode) {
                ForEach(HotkeyMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            if let warning = controller.hotkeyWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }
            if hotkey == .fn {
                HStack {
                    Text("Réglez « Appuyer sur la touche 🌐 pour » sur « Ne rien faire ».")
                        .font(.callout)
                    Spacer()
                    Button("Réglages Clavier…") { Permissions.openSystemSettings(.keyboard) }
                }
            }
        } header: {
            Text("Raccourci")
        } footer: {
            Text(hotkey == .fn
                 ? "Fn demande l'autorisation Accessibilité. Sinon, la touche 🌐 ouvre les emojis ou la dictée d'Apple au lieu de Dictée. Échap annule une dictée en cours."
                 : "⌥ Espace fonctionne sans autorisation particulière. Échap annule une dictée en cours.")
        }
    }

    private var transcriptionSection: some View {
        Section {
            Picker("Modèle", selection: $model) {
                ForEach(modelChoices, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            TextField("Autre modèle", text: $model)
            TextField("Langue (code ISO)", text: $language, prompt: Text("fr"))
            VStack(alignment: .leading, spacing: 4) {
                Text("Vocabulaire")
                TextEditor(text: $vocabulary)
                    .font(.body)
                    .frame(minHeight: 70)
            }
        } header: {
            Text("Transcription")
        } footer: {
            Text("Le vocabulaire aide le modèle à orthographier vos termes (sigles, noms propres, termes juridiques). Langue vide : détection automatique.")
        }
    }

    private var cleanupSection: some View {
        Section {
            Toggle("Nettoyer le texte", isOn: $cleanupEnabled)
            if cleanupEnabled {
                TextField("Modèle de nettoyage", text: $cleanupModel)
            }
        } header: {
            Text("Mise au propre")
        } footer: {
            Text("Second appel qui ponctue et retire les « euh » sans reformuler. Ajoute un peu de délai et de coût.")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("Sons de début et de fin", isOn: $soundsEnabled)
            Toggle("Restaurer le presse-papiers après le collage", isOn: $restoreClipboard)
            Toggle("Lancer Dictée à l'ouverture de session", isOn: $launchAtLogin)
            if let loginMessage {
                Text(loginMessage)
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
        } header: {
            Text("Comportement")
        }
    }

    private var permissionsSection: some View {
        Section {
            LabeledContent("Micro") {
                HStack {
                    statusLabel(granted: microphoneStatus == .granted)
                    if microphoneStatus == .notDetermined {
                        Button("Autoriser…") {
                            Task {
                                _ = await Permissions.requestMicrophone()
                                refreshPermissions()
                            }
                        }
                    } else if microphoneStatus == .denied {
                        Button("Ouvrir les Réglages Système") { Permissions.openSystemSettings(.microphone) }
                    }
                }
            }
            LabeledContent("Accessibilité") {
                HStack {
                    statusLabel(granted: controller.accessibilityGranted)
                    if !controller.accessibilityGranted {
                        Button("Demander…") { Permissions.promptAccessibility() }
                        Button("Ouvrir les Réglages Système") { Permissions.openSystemSettings(.accessibility) }
                    }
                }
            }
        } header: {
            Text("Autorisations")
        } footer: {
            Text("Le micro sert à enregistrer votre voix. L'Accessibilité permet d'écouter la touche Fn et de coller le texte (⌘V) dans l'app au premier plan ; sans elle, le texte est seulement copié. Après une recompilation, il peut falloir retirer puis rajouter Dictée dans la liste.")
        }
    }

    // MARK: - Utilitaires

    private func statusLabel(granted: Bool) -> some View {
        Label(granted ? "Autorisé" : "Non autorisé",
              systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundColor(granted ? .green : .red)
    }

    private var modelChoices: [String] {
        Self.transcriptionModels.contains(model) ? Self.transcriptionModels : Self.transcriptionModels + [model]
    }

    private func refreshPermissions() {
        microphoneStatus = Permissions.microphone
        controller.refreshAccessibility()
    }

    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.saveAPIKey(trimmed)
            savedKeyPreview = KeychainStore.preview(of: KeychainStore.loadAPIKey())
            apiKeyInput = ""
            keyMessage = nil
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        // Appelé aussi quand on resynchronise l'interrupteur sur l'état réel : rien à faire dans ce cas.
        guard enabled != LoginItem.isEnabled else {
            loginMessage = nil
            return
        }
        do {
            try LoginItem.setEnabled(enabled)
            loginMessage = LoginItem.requiresApproval
                ? "Validez Dictée dans Réglages Système > Général > Ouverture."
                : nil
        } catch {
            loginMessage = "Impossible de modifier le lancement automatique : \(error.localizedDescription)"
            launchAtLogin = LoginItem.isEnabled
        }
    }
}
