import Foundation

/// Règles d'insertion du texte dicté à la position du curseur.
enum TextJoiner {
    /// Ajoute une espace avant le texte inséré si le caractère précédent n'en est pas une.
    static func textToInsert(_ text: String, before context: String?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let last = context?.last else { return trimmed }
        if last.isWhitespace || last == "(" || last == "«" || last == "\"" || last == "'" || last == "’" {
            return trimmed
        }
        return " " + trimmed
    }
}
