import AppKit
import ApplicationServices
import CoreGraphics

/// Insertion au curseur (SPEC §5) : presse-papiers + ⌘V simulé, puis restauration du presse-papiers.
@MainActor
final class TextInserter {
    enum Outcome: Equatable {
        /// ⌘V envoyé à l'app au premier plan.
        case pasted
        /// ⌘V impossible (pas d'autorisation Accessibilité, ou personne pour le recevoir) : le texte reste au presse-papiers.
        case copiedOnly
    }

    /// Type « éphémère » (convention nspasteboard.org) : les gestionnaires d'historique l'ignorent.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    var pasteboard: NSPasteboard = .general
    var restoreDelay: TimeInterval = 1.0

    /// Restauration pas encore faite : copie d'origine de l'utilisateur et `changeCount` de notre écriture.
    private var pending: (snapshot: PasteboardSnapshot, changeCount: Int)?

    func insert(_ text: String, restoreClipboard: Bool) async -> Outcome {
        // Sans Accessibilité, le ⌘V simulé est ignoré par macOS. Si Dictée est elle-même au premier plan sans fenêtre,
        // ⌘V n'arriverait nulle part. Dans les deux cas, on laisse le texte au presse-papiers.
        let dicteeIsFrontWithoutWindow =
            NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            && NSApp.keyWindow == nil
        let canPaste = Permissions.accessibilityGranted && !dicteeIsFrontWithoutWindow

        var snapshot: PasteboardSnapshot?
        if canPaste && restoreClipboard {
            if let pending, pending.changeCount == pasteboard.changeCount {
                // La dictée précédente n'est pas encore restaurée : le presse-papiers contient son texte,
                // on garde la vraie copie d'origine.
                snapshot = pending.snapshot
            } else {
                snapshot = PasteboardSnapshot.capture(from: pasteboard)
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if snapshot != nil {
            pasteboard.setData(Data(), forType: Self.transientType)
        }
        let ourChangeCount = pasteboard.changeCount
        pending = snapshot.map { (snapshot: $0, changeCount: ourChangeCount) }

        guard canPaste else { return .copiedOnly }

        // Modificateurs encore tenus (⌥ de ⌥Espace…) : l'app verrait ⌥⌘V. On attend leur relâchement, 0,5 s au plus.
        let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        var waits = 0
        while waits < 25, !CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
            waits += 1
        }
        Self.postPasteShortcut()

        if let snapshot {
            let delay = UInt64(restoreDelay * 1_000_000_000)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                // Une dictée plus récente a repris l'instantané : c'est elle qui restaurera.
                guard let self, self.pending?.changeCount == ourChangeCount else { return }
                self.pending = nil
                TextInserter.restore(snapshot, to: self.pasteboard, ifChangeCountIs: ourChangeCount)
            }
        }
        return .pasted
    }

    /// Restaure l'instantané seulement si personne n'a écrit dans le presse-papiers depuis Dictée.
    @discardableResult
    nonisolated static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard, ifChangeCountIs expected: Int) -> Bool {
        guard pasteboard.changeCount == expected else { return false }
        snapshot.restore(to: pasteboard)
        return true
    }

    /// Simule ⌘V (keyCode 9 = kVK_ANSI_V) dans l'app au premier plan.
    static func postPasteShortcut() {
        let vKey: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
