import Foundation

/// Front d'un raccourci : appui ou relâchement.
enum HotkeyEdge {
    case pressed
    case released
}

enum HotkeyAction: Equatable {
    case start
    case stop
    case ignore
}

/// Logique pure du raccourci (testable sans clavier ni micro).
enum HotkeyLogic {
    /// Une nouvelle dictée est possible depuis `idle` ou `error`, jamais pendant `transcribing` (SPEC §7).
    static func canStart(from state: DictationState) -> Bool {
        state == .idle || state == .error
    }

    /// Traduit un front de raccourci en action, selon le mode et l'état courant.
    static func action(for edge: HotkeyEdge, mode: HotkeyMode, state: DictationState) -> HotkeyAction {
        switch (mode, edge) {
        case (.hold, .pressed):
            return canStart(from: state) ? .start : .ignore
        case (.hold, .released):
            return state == .recording ? .stop : .ignore
        case (.toggle, .pressed):
            if state == .recording { return .stop }
            return canStart(from: state) ? .start : .ignore
        case (.toggle, .released):
            return .ignore
        }
    }
}

/// Suit la touche Fn à partir des événements `flagsChanged`.
/// keyCode 63 = kVK_Function ; le drapeau `.function` indique si elle est enfoncée.
struct FnKeyTracker {
    static let fnKeyCode: UInt16 = 63

    private(set) var isDown = false

    mutating func handle(keyCode: UInt16, functionFlag: Bool) -> HotkeyEdge? {
        guard keyCode == Self.fnKeyCode else { return nil }
        if functionFlag, !isDown {
            isDown = true
            return .pressed
        }
        if !functionFlag, isDown {
            isDown = false
            return .released
        }
        return nil
    }

    mutating func reset() {
        isDown = false
    }
}

extension DictationState {
    /// Symbole SF de l'icône de la barre des menus.
    var menuBarSymbol: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .error: return "exclamationmark.triangle"
        }
    }
}
