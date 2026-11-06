import Foundation

/// Logique pure de la barre de suggestions (SPEC §9, « Barre de suggestions ») : mot en cours de frappe,
/// classement des propositions et texte de remplacement. Sans UIKit, testable.
enum WordPrediction {
    /// Nombre de suggestions affichées.
    static let limit = 3
    /// Longueur minimale du mot en cours avant d'interroger le dictionnaire (une lettre = milliers de résultats).
    static let minimumPartialLength = 2

    /// Caractères qui font partie d'un mot : lettres et trait d'union. L'apostrophe est une frontière
    /// (« l'aud » → « aud »), comme sur le clavier d'iOS en français.
    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character == "-"
    }

    /// Mot en cours de frappe : la fin du texte avant le curseur, jusqu'à la dernière frontière.
    static func partialWord(before context: String?) -> String {
        guard let context, !context.isEmpty else { return "" }
        var word = ""
        for character in context.reversed() {
            guard isWordCharacter(character) else { break }
            word.insert(character, at: word.startIndex)
        }
        return word
    }

    /// Classe et filtre les propositions : d'abord le vocabulaire et l'historique de l'utilisateur, puis le
    /// dictionnaire ; sans le mot lui-même, sans doublon (casse ignorée), `limit` au plus, casse du mot conservée.
    static func rank(partial: String, userTerms: [String], dictionary: [String], limit: Int = limit) -> [String] {
        guard partial.count >= minimumPartialLength else { return [] }
        let lowerPartial = partial.lowercased()
        var seen: Set<String> = [lowerPartial]
        var result: [String] = []

        func add(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > partial.count || trimmed.lowercased() != lowerPartial else { return }
            guard trimmed.lowercased().hasPrefix(lowerPartial) else { return }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(matchCase(of: partial, in: trimmed))
        }

        for term in userTerms where result.count < limit { add(term) }
        for word in dictionary where result.count < limit { add(word) }
        return result
    }

    /// Mots d'un texte utilisateur (vocabulaire, historique), sans ponctuation, pour servir de propositions.
    static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !isWordCharacter($0) }).map(String.init).filter { $0.count > 1 }
    }

    /// Un mot commencé par une majuscule donne une proposition capitalisée ; tout en majuscules (au moins deux
    /// lettres) donne une proposition en majuscules ; sinon la proposition garde sa casse (sigles, noms propres).
    static func matchCase(of partial: String, in suggestion: String) -> String {
        let letters = partial.filter(\.isLetter)
        guard let first = letters.first, first.isUppercase else { return suggestion }
        if letters.count >= 2, letters.allSatisfy(\.isUppercase) { return suggestion.uppercased() }
        if suggestion.first?.isUppercase == true { return suggestion }
        return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
    }

    /// Texte à insérer après avoir effacé le mot en cours : la proposition suivie d'une espace.
    static func replacement(for suggestion: String) -> String {
        suggestion + " "
    }

    /// Identifiant de langue du vérificateur à partir du réglage de dictée (`fr`, `en`, vide = auto) et des
    /// langues disponibles (ex. `fr_FR`, `en_US`, `en_GB`). `fallback` sert quand le réglage est vide ou absent.
    static func checkerLanguage(dictation: String, available: [String], fallback: String?) -> String? {
        let code = dictation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func match(_ wanted: String) -> String? {
            let prefix = wanted.lowercased().replacingOccurrences(of: "-", with: "_")
            if let exact = available.first(where: { $0.lowercased() == prefix }) { return exact }
            let short = String(prefix.prefix(2))
            return available.first(where: { $0.lowercased().hasPrefix(short) })
        }
        if !code.isEmpty, let found = match(code) { return found }
        if let fallback, let found = match(fallback) { return found }
        return nil
    }
}
