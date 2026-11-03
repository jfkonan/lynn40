import Foundation

/// Fournisseur de transcription (SPEC §2 bis), choisi par le réglage `provider`.
/// La valeur brute est celle stockée dans UserDefaults (`dictee.settings.provider`).
enum TranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case openai
    case mistral
    case microsoft

    var id: String { rawValue }

    /// Nom employé dans l'interface et les messages : « OpenAI », « Mistral » ou « Microsoft ».
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .mistral: return "Mistral"
        case .microsoft: return "Microsoft"
        }
    }

    /// Valeur du réglage `provider` : vide, absente ou inconnue → OpenAI (SPEC §3).
    /// Comparaison exacte, comme `@AppStorage`, pour que l'interface et la dictée voient le même fournisseur.
    init(storedValue: String?) {
        self = storedValue.flatMap { TranscriptionProvider(rawValue: $0) } ?? .openai
    }

    /// Compte du Trousseau (service `com.dictee.openai`) : `apiKey` pour OpenAI, inchangé pour la compatibilité (SPEC §4).
    var keychainAccount: String {
        switch self {
        case .openai: return "apiKey"
        case .mistral: return "apiKey.mistral"
        case .microsoft: return "apiKey.microsoft"
        }
    }

    /// Modèle par défaut du fournisseur (SPEC §3).
    var defaultModel: String {
        switch self {
        case .openai: return SharedStore.Default.model
        case .mistral: return SharedStore.Default.mistralModel
        case .microsoft: return SharedStore.Default.microsoftModel
        }
    }

    /// Modèles proposés dans la liste ; la saisie libre reste possible.
    var suggestedModels: [String] {
        switch self {
        case .openai: return ["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]
        case .mistral: return ["voxtral-small-transcribe-3", "voxtral-mini-transcribe-3"]
        case .microsoft: return ["mai-transcribe-2"]
        }
    }

    /// Choix de la liste : les modèles proposés, plus le modèle saisi librement s'il n'y figure pas.
    func modelChoices(including current: String) -> [String] {
        let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !suggestedModels.contains(value) else { return suggestedModels }
        return suggestedModels + [value]
    }

    /// Phrase d'aide affichée sous le choix du fournisseur.
    var note: String {
        switch self {
        case .openai: return "OpenAI : fournisseur par défaut. Sa clé sert aussi au nettoyage du texte."
        case .mistral: return "Mistral : hébergé dans l'UE."
        case .microsoft: return "Microsoft : preview, prix promotionnel jusqu'au 31/12/2026."
        }
    }

    /// Exemple affiché dans le champ de saisie de la clé.
    var keyPlaceholder: String {
        switch self {
        case .openai: return "sk-…"
        case .mistral: return "Clé Mistral"
        case .microsoft: return "Clé Azure Speech"
        }
    }

    /// Clés à proposer dans les réglages : celle du fournisseur choisi, plus celle d'OpenAI si le nettoyage
    /// est activé (le nettoyage passe toujours par OpenAI, SPEC §2.3).
    static func providersNeedingKeys(selected: TranscriptionProvider, cleanupEnabled: Bool) -> [TranscriptionProvider] {
        if cleanupEnabled, selected != .openai {
            return [selected, .openai]
        }
        return [selected]
    }
}
