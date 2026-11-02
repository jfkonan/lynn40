import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: DictationEngine

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
    @AppStorage(SharedStore.Key.sessionMinutes, store: SharedStore.shared.defaults)
    private var sessionMinutes = SharedStore.Default.sessionMinutes

    @State private var apiKeyInput = ""
    @State private var savedKeyHint = ContentView.keyHint(KeychainStore.loadAPIKey())
    @State private var keyMessage: String?

    private static let transcriptionModels = ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]

    var body: some View {
        NavigationStack {
            Form {
                if engine.launchedFromKeyboard && engine.sessionActive {
                    Section {
                        Label("Session active. Revenez à votre app avec « ‹ » en haut à gauche, puis touchez le micro du clavier.", systemImage: "arrow.uturn.left")
                            .font(.callout)
                    }
                }

                sessionSection
                testSection
                apiKeySection
                transcriptionSection
                cleanupSection
                installSection
            }
            .navigationTitle("Dictée")
        }
    }

    // MARK: - Sections

    private var sessionSection: some View {
        Section {
            HStack {
                Circle()
                    .fill(engine.sessionActive ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(engine.sessionActive ? "Session active" : "Session arrêtée")
                Spacer()
                Text(stateLabel).foregroundStyle(.secondary)
            }
            if engine.sessionActive {
                ProgressView(value: Double(engine.inputLevel))
                    .accessibilityLabel("Niveau du micro")
                Button("Arrêter la session", role: .destructive) { engine.endSession() }
            } else {
                Button("Démarrer la session") {
                    Task { await engine.startSessionIfAllowed() }
                }
            }
            if let error = engine.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Session")
        } footer: {
            Text("Tant que la session est active, le micro reste ouvert en arrière-plan (point orange) et le clavier peut dicter sans quitter votre app. Elle s'arrête après \(sessionMinutes) min sans dictée.")
        }
    }

    private var testSection: some View {
        Section("Essai") {
            switch engine.state {
            case .recording:
                Button("Arrêter et transcrire") { engine.stopRecording() }
            case .transcribing:
                HStack { ProgressView(); Text("Transcription…") }
            case .idle, .error:
                Button("Enregistrer un essai") {
                    Task {
                        if !engine.sessionActive { await engine.startSessionIfAllowed() }
                        engine.startRecording()
                    }
                }
            }
            if !engine.lastTranscript.isEmpty {
                Text(engine.lastTranscript)
                    .textSelection(.enabled)
                Button("Copier") { UIPasteboard.general.string = engine.lastTranscript }
            }
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("sk-…", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Enregistrer la clé") { saveKey() }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            if let hint = savedKeyHint {
                HStack {
                    Text("Clé enregistrée : \(hint)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Supprimer", role: .destructive) {
                        KeychainStore.deleteAPIKey()
                        savedKeyHint = nil
                    }
                }
            }
            if let keyMessage {
                Text(keyMessage).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Clé API OpenAI")
        } footer: {
            Text("Stockée dans le Trousseau de cet iPhone uniquement. Le clavier n'y a pas accès.")
        }
    }

    private var transcriptionSection: some View {
        Section {
            Picker("Modèle", selection: $model) {
                ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
            }
            TextField("Autre modèle", text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Langue (code ISO, ex. fr)", text: $language)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            VStack(alignment: .leading) {
                Text("Vocabulaire").font(.subheadline)
                TextEditor(text: $vocabulary)
                    .frame(minHeight: 90)
            }
            Stepper("Fin de session après \(sessionMinutes) min", value: $sessionMinutes, in: 1...120)
        } header: {
            Text("Transcription")
        } footer: {
            Text("Le vocabulaire est transmis au modèle pour qu'il orthographie correctement vos termes (sigles, noms propres, termes juridiques).")
        }
    }

    private var cleanupSection: some View {
        Section {
            Toggle("Nettoyer le texte", isOn: $cleanupEnabled)
            if cleanupEnabled {
                TextField("Modèle de nettoyage", text: $cleanupModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Mise au propre")
        } footer: {
            Text("Second appel qui ponctue et retire les « euh » sans reformuler. Ajoute un peu de délai et de coût.")
        }
    }

    private var installSection: some View {
        Section("Installer le clavier") {
            Text("1. Réglages > Général > Clavier > Claviers > Ajouter un clavier > Dictée.")
            Text("2. Touchez « Dictée » puis activez « Autoriser l'accès complet » (nécessaire pour parler à cette app ; le clavier n'envoie rien sur Internet).")
            Text("3. Dans n'importe quelle app, passez au clavier Dictée avec le globe et touchez le micro.")
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .font(.callout)
    }

    // MARK: - Utilitaires

    private var modelChoices: [String] {
        Self.transcriptionModels.contains(model) ? Self.transcriptionModels : Self.transcriptionModels + [model]
    }

    private var stateLabel: String {
        switch engine.state {
        case .idle: return "Prêt"
        case .recording: return "Enregistrement"
        case .transcribing: return "Transcription"
        case .error: return "Erreur"
        }
    }

    private func saveKey() {
        do {
            try KeychainStore.saveAPIKey(apiKeyInput)
            savedKeyHint = Self.keyHint(KeychainStore.loadAPIKey())
            apiKeyInput = ""
            keyMessage = nil
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    private static func keyHint(_ key: String?) -> String? {
        guard let key, key.count > 8 else { return key == nil ? nil : "••••" }
        return "\(key.prefix(3))…\(key.suffix(4))"
    }
}
