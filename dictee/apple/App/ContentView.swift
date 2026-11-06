import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: DictationEngine

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
    @AppStorage(SharedStore.Key.vocabulary, store: SharedStore.shared.defaults)
    private var vocabulary = SharedStore.Default.vocabulary
    @AppStorage(SharedStore.Key.cleanupEnabled, store: SharedStore.shared.defaults)
    private var cleanupEnabled = SharedStore.Default.cleanupEnabled
    @AppStorage(SharedStore.Key.writingStyle, store: SharedStore.shared.defaults)
    private var writingStyle: WritingStyle = SharedStore.Default.writingStyle
    @AppStorage(SharedStore.Key.cleanupModel, store: SharedStore.shared.defaults)
    private var cleanupModel = SharedStore.Default.cleanupModel
    @AppStorage(SharedStore.Key.sessionMinutes, store: SharedStore.shared.defaults)
    private var sessionMinutes = SharedStore.Default.sessionMinutes

    @State private var historyCount = 0

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
                providerSection
                ForEach(keyProviders) { item in
                    APIKeySection(provider: item)
                }
                transcriptionSection
                cleanupSection
                historySection
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
                    ForEach(TranscriptionProvider.openai.modelChoices(including: model), id: \.self) { Text($0).tag($0) }
                }
                TextField("Autre modèle", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .mistral:
                Picker("Modèle", selection: $mistralModel) {
                    ForEach(TranscriptionProvider.mistral.modelChoices(including: mistralModel), id: \.self) { Text($0).tag($0) }
                }
                TextField("Autre modèle", text: $mistralModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .microsoft:
                LabeledContent("Modèle") {
                    TextField(SharedStore.Default.microsoftModel, text: $microsoftModel)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("Région Azure") {
                    TextField(SharedStore.Default.azureRegion, text: $azureRegion)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text("Fournisseur de transcription")
        } footer: {
            Text(providerFooter)
        }
    }

    private var transcriptionSection: some View {
        Section {
            Picker("Langue de dictée", selection: $language) {
                ForEach(DictationLanguage.choices(including: language)) { choice in
                    Text(choice.label).tag(choice.code)
                }
            }
            TextField("Autre langue (code ISO, ex. es)", text: $language)
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
            Text("Le vocabulaire (termes séparés par des virgules) est transmis au modèle pour qu'il orthographie correctement vos termes (sigles, noms propres, termes juridiques). Mistral et Microsoft en reçoivent les 100 premiers termes.")
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
            if cleanupRequested {
                TextField("Modèle de nettoyage", text: $cleanupModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Mise au propre")
        } footer: {
            Text("Second appel qui ponctue et retire les « euh » sans reformuler. Ajoute un peu de délai et de coût. Il passe toujours par OpenAI, avec la clé OpenAI, quel que soit le fournisseur ; sans clé OpenAI, il est sauté. Un style autre que « Brut » (Formel, Courriel, Décontracté) active ce second appel même si « Nettoyer le texte » est désactivé ; il se choisit aussi depuis le clavier.")
        }
    }

    private var historySection: some View {
        Section {
            Button("Effacer l'historique", role: .destructive) {
                SharedStore.shared.clearHistory()
                historyCount = 0
            }
        } header: {
            Text("Historique")
        } footer: {
            Text(historyFooter)
        }
        // Relu à l'affichage et après chaque dictée (l'historique est aussi effaçable depuis le clavier).
        .onAppear { historyCount = SharedStore.shared.history.count }
        .onChange(of: engine.lastTranscript) { _ in historyCount = SharedStore.shared.history.count }
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

    /// Nettoyage demandé : « Nettoyer le texte » activé ou style autre que « Brut » (SPEC §2).
    private var cleanupRequested: Bool {
        TranscriptionRules.isCleanupRequested(enabled: cleanupEnabled, style: writingStyle)
    }

    /// Clé du fournisseur choisi, plus celle d'OpenAI si le nettoyage est demandé.
    private var keyProviders: [TranscriptionProvider] {
        TranscriptionProvider.providersNeedingKeys(selected: provider, cleanupEnabled: cleanupRequested)
    }

    private var historyFooter: String {
        let base = "Les \(SharedStore.historyLimit) dernières transcriptions restent sur cet iPhone (App Group) pour être réinsérées depuis le panneau ☰ du clavier."
        switch historyCount {
        case 0: return base + " Historique vide."
        case 1: return base + " 1 transcription enregistrée."
        default: return base + " \(historyCount) transcriptions enregistrées."
        }
    }

    private var providerFooter: String {
        if provider == .microsoft {
            return provider.note + " Indiquez la région de votre ressource Azure Speech (ex. westeurope, swedencentral)."
        }
        return provider.note
    }

    private var stateLabel: String {
        switch engine.state {
        case .idle: return "Prêt"
        case .recording: return "Enregistrement"
        case .transcribing: return "Transcription"
        case .error: return "Erreur"
        }
    }
}

/// Clé API d'un fournisseur : saisie, aperçu `sk-…abcd` et suppression (SPEC §4).
private struct APIKeySection: View {
    let provider: TranscriptionProvider

    @State private var input = ""
    @State private var savedHint: String?
    @State private var message: String?

    var body: some View {
        Section {
            SecureField(provider.keyPlaceholder, text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Enregistrer la clé") { save() }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let hint = savedHint {
                HStack {
                    Text("Clé enregistrée : \(hint)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Supprimer", role: .destructive) {
                        KeychainStore.deleteAPIKey(for: provider)
                        savedHint = nil
                    }
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Clé API \(provider.displayName)")
        } footer: {
            Text(footer)
        }
        // Lu à l'affichage plutôt que dans `init`, que SwiftUI rappelle à chaque mise à jour de l'écran.
        .onAppear { savedHint = KeychainStore.preview(of: KeychainStore.loadAPIKey(for: provider)) }
    }

    private var footer: String {
        let base = "Stockée dans le Trousseau de cet iPhone uniquement. Le clavier n'y a pas accès."
        switch provider {
        case .openai: return base + " Elle sert aussi au nettoyage du texte."
        case .mistral: return base
        case .microsoft: return base + " Clé de votre ressource Azure AI Speech."
        }
    }

    private func save() {
        do {
            try KeychainStore.saveAPIKey(input, for: provider)
            savedHint = KeychainStore.preview(of: KeychainStore.loadAPIKey(for: provider))
            input = ""
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}
