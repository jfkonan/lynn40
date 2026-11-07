import AppKit
import Combine
import SwiftUI

/// Réglages de l'app Mac : fournisseur et clés API, raccourci, transcription, nettoyage, comportement, autorisations.
struct SettingsView: View {
    @ObservedObject var controller: DictationController

    // Réglages communs (SPEC §3), mêmes clés que sur iOS.
    @AppStorage(SharedStore.Key.provider, store: SharedStore.shared.defaults)
    private var provider: TranscriptionProvider = .openai
    @AppStorage(SharedStore.Key.model, store: SharedStore.shared.defaults)
    private var model = SharedStore.Default.model
    @AppStorage(SharedStore.Key.mistralModel, store: SharedStore.shared.defaults)
    private var mistralModel = SharedStore.Default.mistralModel
    @AppStorage(SharedStore.Key.microsoftModel, store: SharedStore.shared.defaults)
    private var microsoftModel = SharedStore.Default.microsoftModel
    @AppStorage(SharedStore.Key.azureRegion, store: SharedStore.shared.defaults)
    private var azureRegion = SharedStore.Default.azureRegion
    @AppStorage(SharedStore.Key.language, store: SharedStore.shared.defaults)
    private var language = SharedStore.Default.language
    @AppStorage(SharedStore.Key.streamingEnabled, store: SharedStore.shared.defaults)
    private var streamingEnabled = SharedStore.Default.streamingEnabled
    @AppStorage(SharedStore.Key.vocabulary, store: SharedStore.shared.defaults)
    private var vocabulary = SharedStore.Default.vocabulary
    @AppStorage(SharedStore.Key.cleanupEnabled, store: SharedStore.shared.defaults)
    private var cleanupEnabled = SharedStore.Default.cleanupEnabled
    @AppStorage(SharedStore.Key.writingStyle, store: SharedStore.shared.defaults)
    private var writingStyle: WritingStyle = SharedStore.Default.writingStyle
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

    @State private var loginMessage: String?
    @State private var microphoneStatus = Permissions.microphone

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            providerSection
            ForEach(keyProviders) { item in
                APIKeySection(provider: item)
            }
            shortcutSection
            transcriptionSection
            cleanupSection
            behaviorSection
            permissionsSection
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 700)
        .onAppear {
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

    private var providerSection: some View {
        Section {
            Picker("Fournisseur", selection: $provider) {
                ForEach(TranscriptionProvider.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            switch provider {
            case .openai:
                Picker("Modèle", selection: $model) {
                    ForEach(TranscriptionProvider.openai.modelChoices(including: model), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                TextField("Autre modèle", text: $model, prompt: Text(SharedStore.Default.model))
            case .mistral:
                Picker("Modèle", selection: $mistralModel) {
                    ForEach(TranscriptionProvider.mistral.modelChoices(including: mistralModel), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                TextField("Autre modèle", text: $mistralModel, prompt: Text(SharedStore.Default.mistralModel))
            case .microsoft:
                TextField("Modèle", text: $microsoftModel, prompt: Text(SharedStore.Default.microsoftModel))
                TextField("Région Azure", text: $azureRegion, prompt: Text(SharedStore.Default.azureRegion))
            }
        } header: {
            Text("Fournisseur de transcription")
        } footer: {
            Text(providerFooter)
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
            Picker("Langue de dictée", selection: $language) {
                ForEach(DictationLanguage.choices(including: language)) { choice in
                    Text(choice.label).tag(choice.code)
                }
            }
            TextField("Autre langue (code ISO)", text: $language, prompt: Text("es"))
            Toggle("Transcription en continu", isOn: $streamingEnabled)
            VStack(alignment: .leading, spacing: 4) {
                Text("Vocabulaire")
                TextEditor(text: $vocabulary)
                    .font(.body)
                    .frame(minHeight: 70)
            }
        } header: {
            Text("Transcription")
        } footer: {
            Text("Le vocabulaire (termes séparés par des virgules) aide le modèle à orthographier vos termes (sigles, noms propres, termes juridiques). Mistral et Microsoft en reçoivent les 100 premiers termes. Langue vide : détection automatique. Transcription en continu : l'audio est transcrit pendant que vous parlez, le texte arrive dès le relâchement (OpenAI, Mistral ; plus cher : 0,017 $/min chez OpenAI). En cas d'échec, l'envoi du fichier prend le relais.")
        }
    }

    private var cleanupSection: some View {
        Section {
            Toggle("Nettoyer le texte", isOn: $cleanupEnabled)
            Picker("Style d'écriture", selection: $writingStyle) {
                ForEach(WritingStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            if TranscriptionRules.isCleanupRequested(enabled: cleanupEnabled, style: writingStyle) {
                TextField("Modèle de nettoyage", text: $cleanupModel)
            }
        } header: {
            Text("Mise au propre")
        } footer: {
            Text("Second appel qui ponctue et retire les « euh » sans reformuler. Ajoute un peu de délai et de coût. Il passe toujours par OpenAI, avec la clé OpenAI, quel que soit le fournisseur ; sans clé OpenAI, il est sauté. Un style autre que « Brut » active ce second appel même si « Nettoyer le texte » est désactivé.")
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

    /// Clé du fournisseur choisi, plus celle d'OpenAI si le nettoyage est demandé (réglage ou style autre que « Brut »).
    private var keyProviders: [TranscriptionProvider] {
        TranscriptionProvider.providersNeedingKeys(
            selected: provider,
            cleanupEnabled: TranscriptionRules.isCleanupRequested(enabled: cleanupEnabled, style: writingStyle)
        )
    }

    private var providerFooter: String {
        if provider == .microsoft {
            return provider.note + " Indiquez la région de votre ressource Azure Speech (ex. westeurope, swedencentral)."
        }
        return provider.note
    }

    private func refreshPermissions() {
        microphoneStatus = Permissions.microphone
        controller.refreshAccessibility()
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

/// Clé API d'un fournisseur : aperçu `sk-…abcd`, suppression et saisie (SPEC §4).
private struct APIKeySection: View {
    let provider: TranscriptionProvider

    @State private var input = ""
    @State private var savedPreview: String?
    @State private var message: String?

    var body: some View {
        Section {
            if let preview = savedPreview {
                LabeledContent("Clé enregistrée") {
                    HStack {
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                        Button("Supprimer", role: .destructive) {
                            KeychainStore.deleteAPIKey(for: provider)
                            savedPreview = nil
                        }
                    }
                }
            }
            SecureField(savedPreview == nil ? "Clé API" : "Nouvelle clé", text: $input, prompt: Text(provider.keyPlaceholder))
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Enregistrer la clé", action: save)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        } header: {
            Text("Clé API \(provider.displayName)")
        } footer: {
            Text(footer)
        }
        .onAppear { savedPreview = KeychainStore.preview(of: KeychainStore.loadAPIKey(for: provider)) }
    }

    private var footer: String {
        switch provider {
        case .openai:
            return "Stockée dans le Trousseau de ce Mac. Elle n'est envoyée qu'à OpenAI (transcription et nettoyage du texte)."
        case .mistral:
            return "Stockée dans le Trousseau de ce Mac. Elle n'est envoyée qu'à Mistral."
        case .microsoft:
            return "Clé de votre ressource Azure AI Speech, stockée dans le Trousseau de ce Mac. Elle n'est envoyée qu'à Microsoft."
        }
    }

    private func save() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.saveAPIKey(trimmed, for: provider)
            savedPreview = KeychainStore.preview(of: KeychainStore.loadAPIKey(for: provider))
            input = ""
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}
