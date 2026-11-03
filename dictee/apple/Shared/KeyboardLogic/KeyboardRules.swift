import Foundation

// Règles de frappe du clavier (SPEC §9) : majuscule, majuscule automatique, double espace, libellé de ⏎.
// Fonctions pures, sans UIKit, testées dans DicteeTests. Les temps sont en secondes (horloge monotone).

/// État de la touche ⇧.
enum ShiftState: Hashable, Sendable {
    case off
    /// Une seule majuscule (toucher simple ou majuscule automatique).
    case once
    /// Verrouillage des majuscules (double toucher).
    case locked
}

/// Majuscule : un toucher = une majuscule, double toucher = verrouillage, toucher en verrouillage = arrêt.
struct ShiftLogic: Equatable, Sendable {
    /// Délai maximal entre deux touchers pour un double toucher.
    static let doubleTapInterval: TimeInterval = 0.35

    private(set) var state: ShiftState = .off
    private var lastTapTime: TimeInterval?

    init(state: ShiftState = .off) {
        self.state = state
    }

    mutating func tap(at time: TimeInterval) {
        if state == .locked {
            state = .off
            lastTapTime = nil
            return
        }
        if let last = lastTapTime, time - last >= 0, time - last <= Self.doubleTapInterval {
            state = .locked
            lastTapTime = nil
            return
        }
        state = state == .off ? .once : .off
        lastTapTime = time
    }

    /// Après chaque frappe ou déplacement du curseur : la majuscule simple est consommée et la majuscule
    /// automatique est réévaluée ; le verrouillage, lui, est conservé.
    mutating func applyAutoCapitalization(_ shouldCapitalize: Bool) {
        guard state != .locked else { return }
        state = shouldCapitalize ? .once : .off
    }
}

/// Équivalent sans UIKit de `UITextAutocapitalizationType`.
enum AutoCapitalizationMode: Hashable, Sendable {
    case none
    case words
    case sentences
    case allCharacters
}

enum AutoCapitalization {
    /// Ponctuation de fin de phrase suivie d'une espace : la lettre suivante prend une majuscule.
    static let sentenceTerminators: Set<Character> = [".", "?", "!", "…"]

    /// Majuscule automatique (SPEC §9) : en début de champ et après `. ? !` suivis d'une espace, selon le mode du champ.
    /// `contextBefore` est le texte avant le curseur (`documentContextBeforeInput`) ; `nil` = début de champ.
    static func shouldCapitalize(mode: AutoCapitalizationMode, contextBefore: String?) -> Bool {
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            guard let last = contextBefore?.last else { return true }
            return last.isWhitespace
        case .sentences:
            guard let context = contextBefore, let last = context.last else { return true }
            if last.isNewline { return true }
            guard last.isWhitespace else { return false }
            guard let previous = context.last(where: { !$0.isWhitespace }) else { return true }
            return sentenceTerminators.contains(previous)
        }
    }
}

/// Double espace = « . » (comme iOS).
enum DoubleSpaceRule {
    /// Délai maximal entre les deux espaces.
    static let interval: TimeInterval = 0.8

    /// Vrai si l'espace qu'on vient de toucher doit remplacer l'espace précédente par « . » :
    /// la touche précédente était une espace tapée il y a moins de `interval`, et cette espace suit un mot
    /// (lettre, chiffre ou signe fermant), pas déjà une ponctuation ni une autre espace.
    static func shouldInsertPeriod(contextBefore: String?, secondsSinceLastSpace: TimeInterval?) -> Bool {
        guard let elapsed = secondsSinceLastSpace, elapsed >= 0, elapsed <= interval,
              let context = contextBefore, context.last == " " else { return false }
        let withoutSpace = context.dropLast()
        guard let previous = withoutSpace.last else { return false }
        return previous.isLetter || previous.isNumber || ")]»\"'’".contains(previous)
    }

    /// Texte qui remplace l'espace effacée.
    static let replacement = ". "
}

/// Équivalent sans UIKit de `UIReturnKeyType`.
enum ReturnKeyKind: Hashable, Sendable, CaseIterable {
    case standard
    case go
    case google
    case join
    case next
    case route
    case search
    case send
    case yahoo
    case done
    case emergencyCall
    case continueAction

    /// Libellé de la touche ⏎ (SPEC §9).
    var label: String {
        switch self {
        case .standard: return "retour"
        case .go: return "aller"
        case .google, .search, .yahoo: return "rechercher"
        case .join: return "rejoindre"
        case .next: return "suivant"
        case .route: return "itinéraire"
        case .send: return "envoyer"
        case .done: return "OK"
        case .emergencyCall: return "urgence"
        case .continueAction: return "continuer"
        }
    }

    /// Touche mise en avant (bleue), comme sur iOS, pour les actions autres que le retour à la ligne et « suivant ».
    var isProminent: Bool {
        switch self {
        case .standard, .next: return false
        default: return true
        }
    }
}
