import SwiftUI
import UIKit

/// Barre de suggestions (SPEC §9) : complète le mot en cours de frappe avec `UITextChecker`, dans la langue de
/// dictée, après le vocabulaire et l'historique de l'utilisateur (sigles juridiques, noms propres). Pas de réseau,
/// pas de dictionnaire embarqué : léger pour une extension clavier. Ce n'est pas une prédiction du mot suivant.
@MainActor
final class PredictionModel: ObservableObject {
    @Published private(set) var suggestions: [String] = []
    /// Mot en cours au moment du calcul (effacé avant l'insertion de la proposition).
    private(set) var partial = ""

    private weak var controller: KeyboardViewController?
    private let store = SharedStore.shared
    private let checker = UITextChecker()
    private var pending: DispatchWorkItem?
    /// Coalesce les rafales de frappe à deux pouces (plusieurs insertions par image).
    private static let coalesceDelay: TimeInterval = 0.05

    init(controller: KeyboardViewController) {
        self.controller = controller
    }

    func disappear() {
        pending?.cancel()
        pending = nil
        clear()
    }

    /// À appeler après toute modification du champ ; le contexte est relu dans le bloc différé.
    func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.refresh()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceDelay, execute: work)
    }

    /// L'utilisateur a touché une proposition : remplace le mot en cours par la proposition suivie d'une espace.
    func accept(_ suggestion: String) {
        guard let controller else { return }
        pending?.cancel()
        pending = nil
        // Mot relu au moment du toucher : `partial` peut avoir 50 ms de retard sur la frappe.
        let current = WordPrediction.partialWord(before: controller.contextBeforeInput)
        for _ in 0..<current.count { controller.deleteBackward() }
        controller.insert(WordPrediction.replacement(for: suggestion))
        clear()
        controller.documentChangedByPrediction()
    }

    // MARK: - Calcul

    private func refresh() {
        guard let controller, controller.predictionsAllowed else {
            clear()
            return
        }
        let word = WordPrediction.partialWord(before: controller.contextBeforeInput)
        guard word.count >= WordPrediction.minimumPartialLength else {
            clear()
            return
        }
        let language = WordPrediction.checkerLanguage(
            dictation: store.language,
            available: UITextChecker.availableLanguages,
            fallback: controller.primaryLanguage ?? Locale.current.identifier
        )
        var dictionary: [String] = []
        if let language {
            let probe = word as NSString
            dictionary = checker.completions(
                forPartialWordRange: NSRange(location: 0, length: probe.length),
                in: word,
                language: language
            ) ?? []
        }
        let ranked = WordPrediction.rank(partial: word, userTerms: userTerms, dictionary: dictionary)
        partial = word
        if ranked != suggestions { suggestions = ranked }
    }

    /// Mots du vocabulaire puis des dernières transcriptions (`Core/` n'est pas compilé dans le clavier).
    private var userTerms: [String] {
        var terms = WordPrediction.words(in: store.vocabulary)
        for transcript in store.history { terms.append(contentsOf: WordPrediction.words(in: transcript.text)) }
        return terms
    }

    private func clear() {
        partial = ""
        if !suggestions.isEmpty { suggestions = [] }
    }
}
