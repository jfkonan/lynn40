import Foundation

/// Langue de dictée (SPEC §3, réglage `language`) : `fr`, `en`, ou vide = détection automatique.
/// Liste commune au clavier (panneau ☰), à l'app iOS et à l'app Mac ; une autre langue reste possible en saisie libre.
struct DictationLanguage: Identifiable, Equatable {
    let code: String
    let label: String
    var id: String { code }

    static let french = DictationLanguage(code: "fr", label: "Français")
    static let english = DictationLanguage(code: "en", label: "Anglais")
    static let automatic = DictationLanguage(code: "", label: "Détection auto")

    static let standard: [DictationLanguage] = [french, english, automatic]

    /// Les trois choix du cahier des charges, plus `code` s'il est autre (ex. `es`), pour que le réglage courant
    /// soit toujours sélectionnable.
    static func choices(including code: String) -> [DictationLanguage] {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !standard.contains(where: { $0.code == trimmed }) else { return standard }
        return standard + [DictationLanguage(code: trimmed, label: trimmed)]
    }

    /// Vrai si `code` n'est pas l'un des trois choix standard (langue saisie librement).
    static func isCustom(_ code: String) -> Bool {
        !standard.contains(where: { $0.code == code.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}
