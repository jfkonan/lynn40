import Foundation

/// Règles du pipeline de SPEC §2, sans réseau ni matériel, donc testables.
/// Utilisées par l'app Mac ; portables iOS + macOS (aucune API propre à une plateforme).
enum TranscriptionRules {
    /// Au-delà : arrêt automatique et transcription (limite de 25 Mo d'OpenAI).
    static let maxRecordingDuration: TimeInterval = 12 * 60
    /// En dessous : abandon sans appel réseau et sans erreur.
    static let minRecordingDuration: TimeInterval = 0.3

    enum RuleError: LocalizedError, Equatable {
        case noSpeech

        var errorDescription: String? {
            switch self {
            case .noSpeech: return "Aucune parole détectée."
            }
        }
    }

    /// Faut-il envoyer l'enregistrement au fournisseur de transcription ? (SPEC §2.1)
    static func shouldTranscribe(duration: TimeInterval) -> Bool {
        duration >= minRecordingDuration
    }

    /// Faut-il lancer le nettoyage ? Inutile sur un texte brut vide.
    static func shouldCleanUp(enabled: Bool, raw: String) -> Bool {
        enabled && !trimmed(raw).isEmpty
    }

    /// Variante qui tient compte de la clé OpenAI : le nettoyage passe toujours par OpenAI et,
    /// sans clé OpenAI, il est sauté sans erreur (SPEC §2.3).
    static func shouldCleanUp(enabled: Bool, raw: String, openAIKey: String?) -> Bool {
        shouldCleanUp(enabled: enabled, raw: raw) && !trimmed(openAIKey ?? "").isEmpty
    }

    /// Texte final (SPEC §2.3 et §2.4) : le texte nettoyé s'il n'est pas vide, sinon le texte brut.
    /// `cleaned` vaut `nil` si le nettoyage est désactivé ou a échoué. Texte final vide : `RuleError.noSpeech`.
    static func finalText(raw: String, cleaned: String?) throws -> String {
        let cleanedText = trimmed(cleaned ?? "")
        let text = cleanedText.isEmpty ? trimmed(raw) : cleanedText
        guard !text.isEmpty else { throw RuleError.noSpeech }
        return text
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
