import Foundation

enum DictationState: String {
    case idle
    case recording
    case transcribing
    case error
}

struct Transcript: Codable, Equatable {
    let id: String
    let text: String
    let createdAt: Date
}

extension Transcript: Identifiable {}

/// État et réglages partagés entre l'app et le clavier (UserDefaults de l'App Group).
/// Les clés API ne sont PAS stockées ici : elles restent dans le Trousseau de l'app (KeychainStore).
final class SharedStore: @unchecked Sendable {
    static let shared = SharedStore()

    /// Nombre de transcriptions gardées dans l'historique (SPEC §2, « Historique »).
    static let historyLimit = 10

    enum Key {
        static let state = "dictee.state"
        static let errorMessage = "dictee.errorMessage"
        static let sessionExpiresAt = "dictee.sessionExpiresAt"
        static let latestTranscript = "dictee.latestTranscript"
        static let consumedTranscriptID = "dictee.consumedTranscriptID"
        /// Historique des dernières transcriptions (JSON, la plus récente en premier).
        static let history = "dictee.history"
        // Réglages
        static let provider = "dictee.settings.provider"
        static let model = "dictee.settings.model"
        static let mistralModel = "dictee.settings.mistralModel"
        static let microsoftModel = "dictee.settings.microsoftModel"
        static let azureRegion = "dictee.settings.azureRegion"
        static let language = "dictee.settings.language"
        static let vocabulary = "dictee.settings.vocabulary"
        static let cleanupEnabled = "dictee.settings.cleanupEnabled"
        static let writingStyle = "dictee.settings.writingStyle"
        static let cleanupModel = "dictee.settings.cleanupModel"
        static let sessionMinutes = "dictee.settings.sessionMinutes"
    }

    enum Default {
        static let provider = "openai"
        static let model = "gpt-transcribe"
        static let mistralModel = "voxtral-small-transcribe-3"
        static let microsoftModel = "mai-transcribe-2"
        static let azureRegion = "eastus"
        static let language = "fr"
        static let vocabulary = "OHADA, AUSCGIE, AUDCG, AUPCAP, AUPSRVE, CCJA, SARL, SA, SAS, SNC, GIE, RCCM, assemblée générale, conseil d'administration, commissaire aux comptes, gérant, statuts, capital social"
        static let cleanupEnabled = false
        static let writingStyle = WritingStyle.brut
        static let cleanupModel = "gpt-4o-mini"
        static let sessionMinutes = 10
    }

    let defaults: UserDefaults

    /// `defaults` est injectable pour les tests.
    init(defaults: UserDefaults? = AppGroup.defaults) {
        self.defaults = defaults ?? .standard
    }

    // MARK: - État de la dictée

    var state: DictationState {
        get { DictationState(rawValue: defaults.string(forKey: Key.state) ?? "") ?? .idle }
        set { defaults.set(newValue.rawValue, forKey: Key.state) }
    }

    var errorMessage: String? {
        get { defaults.string(forKey: Key.errorMessage) }
        set { defaults.set(newValue, forKey: Key.errorMessage) }
    }

    /// Mis à jour toutes les quelques secondes par l'app tant que la session audio tourne.
    var sessionExpiresAt: Date? {
        get { defaults.object(forKey: Key.sessionExpiresAt) as? Date }
        set { defaults.set(newValue, forKey: Key.sessionExpiresAt) }
    }

    func isSessionAlive(now: Date = Date()) -> Bool {
        guard let expiry = sessionExpiresAt else { return false }
        return expiry > now
    }

    // MARK: - Transcriptions

    var latestTranscript: Transcript? {
        get {
            guard let data = defaults.data(forKey: Key.latestTranscript) else { return nil }
            return try? JSONDecoder().decode(Transcript.self, from: data)
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) }
            defaults.set(data, forKey: Key.latestTranscript)
        }
    }

    var consumedTranscriptID: String? {
        get { defaults.string(forKey: Key.consumedTranscriptID) }
        set { defaults.set(newValue, forKey: Key.consumedTranscriptID) }
    }

    /// Dernière transcription pas encore insérée, si elle est assez récente.
    /// La limite d'âge évite d'insérer un vieux texte dans un champ sans rapport.
    func unconsumedTranscript(maxAge: TimeInterval = 120, now: Date = Date()) -> Transcript? {
        guard let transcript = latestTranscript,
              transcript.id != consumedTranscriptID,
              now.timeIntervalSince(transcript.createdAt) <= maxAge else { return nil }
        return transcript
    }

    func markConsumed(_ transcript: Transcript) {
        consumedTranscriptID = transcript.id
    }

    // MARK: - Historique (SPEC §2, « Historique »)

    /// Les 10 dernières transcriptions, la plus récente en premier. Données illisibles → historique vide.
    var history: [Transcript] {
        guard let data = defaults.data(forKey: Key.history),
              let items = try? JSONDecoder().decode([Transcript].self, from: data) else { return [] }
        return Array(items.prefix(Self.historyLimit))
    }

    /// Ajoute une transcription en tête de l'historique (10 au maximum).
    func addToHistory(_ transcript: Transcript) {
        let updated = Self.updatedHistory(adding: transcript, to: history)
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: Key.history)
    }

    func clearHistory() {
        defaults.removeObject(forKey: Key.history)
    }

    /// Règle pure : la nouvelle transcription en tête, sans doublon d'identifiant, `limit` éléments au maximum.
    static func updatedHistory(adding transcript: Transcript, to existing: [Transcript], limit: Int = SharedStore.historyLimit) -> [Transcript] {
        let others = existing.filter { $0.id != transcript.id }
        return Array(([transcript] + others).prefix(max(limit, 0)))
    }

    // MARK: - Réglages

    /// Valeur brute du réglage `provider`, telle qu'elle est stockée.
    var providerSetting: String { defaults.string(forKey: Key.provider) ?? Default.provider }

    /// Fournisseur choisi : valeur inconnue ou vide → OpenAI (SPEC §3). Modifiable depuis le panneau rapide du clavier.
    var provider: TranscriptionProvider {
        get { TranscriptionProvider(storedValue: providerSetting) }
        set { defaults.set(newValue.rawValue, forKey: Key.provider) }
    }

    /// Modèle OpenAI.
    var model: String { nonEmpty(Key.model) ?? Default.model }
    var mistralModel: String { nonEmpty(Key.mistralModel) ?? Default.mistralModel }
    var microsoftModel: String { nonEmpty(Key.microsoftModel) ?? Default.microsoftModel }
    var azureRegion: String { nonEmpty(Key.azureRegion) ?? Default.azureRegion }

    /// Langue : vide = détection automatique. Modifiable depuis le panneau rapide du clavier.
    var language: String {
        get { defaults.string(forKey: Key.language) ?? Default.language }
        set { defaults.set(newValue, forKey: Key.language) }
    }

    var vocabulary: String { defaults.string(forKey: Key.vocabulary) ?? Default.vocabulary }
    var cleanupEnabled: Bool { defaults.object(forKey: Key.cleanupEnabled) as? Bool ?? Default.cleanupEnabled }

    /// Style d'écriture : valeur inconnue ou absente → brut (SPEC §3). Modifiable depuis le clavier.
    var writingStyle: WritingStyle {
        get { WritingStyle(storedValue: defaults.string(forKey: Key.writingStyle)) }
        set { defaults.set(newValue.rawValue, forKey: Key.writingStyle) }
    }

    var cleanupModel: String { nonEmpty(Key.cleanupModel) ?? Default.cleanupModel }
    var sessionMinutes: Int {
        let value = defaults.object(forKey: Key.sessionMinutes) as? Int ?? Default.sessionMinutes
        return min(max(value, 1), 120)
    }

    private func nonEmpty(_ key: String) -> String? {
        guard let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
