import Foundation

/// Correction automatique à l'espace (SPEC §9, « Correction automatique ») : logique pure, testable.
/// Le vérificateur système fournit les propositions ; ici on décide quels mots sont corrigibles et quelle
/// proposition est assez proche pour remplacer le mot sans surprise.
enum AutoCorrection {
    /// Signes qui, comme l'espace, terminent un mot et déclenchent la correction.
    static let boundaryPunctuation = ".,;:!?"
    /// En dessous, on ne corrige pas : trop court pour être sûr (« la » → « le » serait une plaie).
    static let minimumLength = 3

    struct Correction: Equatable {
        let original: String
        let corrected: String
        /// Espace ou ponctuation tapée après le mot, réinsérée à l'annulation.
        let boundary: String
    }

    /// Vrai pour une espace ou un signe de `boundaryPunctuation` tapé seul.
    static func isBoundary(_ text: String) -> Bool {
        text == " " || (text.count == 1 && boundaryPunctuation.contains(text))
    }

    /// Un mot est corrigible s'il est fait de lettres seulement, assez long, sans majuscule interne ni tout en
    /// majuscules (sigles, noms composés), et absent des mots protégés (vocabulaire, historique), casse ignorée.
    static func isCandidate(_ word: String, protected: [String]) -> Bool {
        guard word.count >= minimumLength, word.allSatisfy(\.isLetter) else { return false }
        let letters = Array(word)
        if letters.allSatisfy(\.isUppercase) { return false }
        if letters.dropFirst().contains(where: \.isUppercase) { return false }
        let lower = word.lowercased()
        return !protected.contains { $0.lowercased() == lower }
    }

    /// Distance maximale acceptée entre le mot et sa correction : 1 pour un mot court, 2 à partir de 5 lettres.
    static func maximumDistance(for word: String) -> Int {
        word.count >= 5 ? 2 : 1
    }

    /// Première proposition assez proche du mot (lettres, espace, trait d'union ou apostrophe seulement),
    /// avec la casse du mot d'origine ; `nil` s'il n'y en a pas.
    static func pick(for word: String, guesses: [String]) -> String? {
        let lower = word.lowercased()
        let limit = maximumDistance(for: word)
        for guess in guesses {
            let trimmed = guess.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.lowercased() != lower else { continue }
            guard trimmed.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" || $0 == "’" }) else { continue }
            guard levenshtein(lower, trimmed.lowercased()) <= limit else { continue }
            return WordPrediction.matchCase(of: word, in: trimmed)
        }
        return nil
    }

    /// Le texte avant le curseur se termine-t-il encore par la correction suivie de sa frontière ?
    /// Sinon, l'utilisateur a continué à écrire et l'annulation n'a plus de sens.
    static func isStillApplied(_ correction: Correction, before context: String?) -> Bool {
        guard let context else { return false }
        return context.hasSuffix(correction.corrected + correction.boundary)
    }

    /// Distance d'édition (insertion, suppression, substitution), sur des caractères.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var previous = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            current[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[t.count]
    }
}
