import AppKit
import Carbon

/// Installe le raccourci choisi et traduit les événements clavier en fronts (appui / relâchement).
///
/// - Fn : moniteurs NSEvent `.flagsChanged` (global pour les autres apps, local pour la nôtre).
///   Les moniteurs globaux d'événements clavier ne reçoivent rien sans l'autorisation Accessibilité.
/// - ⌥Espace : raccourci Carbon, sans autorisation.
/// - Échap pendant l'enregistrement : raccourcis Carbon temporaires (consomment la touche), Échap seule et ⌥Échap
///   (⌥ encore tenue avec ⌥Espace en mode « maintenir »), doublés d'un moniteur global si Carbon échoue.
@MainActor
final class HotkeyManager {
    var onEdge: ((HotkeyEdge) -> Void)?
    var onEscape: (() -> Void)?
    /// Fn maintenue puis autre touche (Fn+F1, Fn+flèche…) : c'est un raccourci système, pas une dictée.
    var onFnChord: (() -> Void)?

    static let escapeKeyCode: UInt16 = 53 // kVK_Escape

    private var fnTracker = FnKeyTracker()
    private var hotkeyMonitors: [Any] = []
    private var escapeMonitors: [Any] = []
    private let comboHotKey = CarbonHotKey(id: 1)
    private let escapeHotKey = CarbonHotKey(id: 2)
    /// Carbon exige les modificateurs exacts : ⌥Échap doit être enregistré à part.
    private let escapeOptionHotKey = CarbonHotKey(id: 3)
    private var escapeEnabled = false
    /// Le dernier appui de Fn a servi à un raccourci (Fn+flèche, Fn+F1…).
    private var chorded = false

    var lastPressWasChord: Bool { chorded }

    init() {
        comboHotKey.onEdge = { [weak self] edge in
            self?.onEdge?(edge)
        }
        escapeHotKey.onEdge = { [weak self] edge in
            if edge == .pressed { self?.onEscape?() }
        }
        escapeOptionHotKey.onEdge = { [weak self] edge in
            if edge == .pressed { self?.onEscape?() }
        }
    }

    /// Installe le raccourci. Renvoie false si la combinaison est déjà prise par une autre app.
    @discardableResult
    func install(_ choice: HotkeyChoice) -> Bool {
        uninstall()
        switch choice {
        case .fn:
            let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
            let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handle(event)
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handle(event)
                return event
            }
            hotkeyMonitors = [global, local].compactMap { $0 }
            return !hotkeyMonitors.isEmpty
        case .optionSpace:
            return comboHotKey.register(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        }
    }

    func uninstall() {
        for monitor in hotkeyMonitors {
            NSEvent.removeMonitor(monitor)
        }
        hotkeyMonitors = []
        comboHotKey.unregister()
        fnTracker.reset()
        chorded = false
    }

    /// Capture Échap uniquement pendant l'enregistrement, pour ne pas la voler aux autres apps le reste du temps.
    func setEscapeEnabled(_ enabled: Bool) {
        guard enabled != escapeEnabled else { return }
        escapeEnabled = enabled
        if enabled {
            escapeHotKey.register(keyCode: UInt32(kVK_Escape), modifiers: 0)
            escapeOptionHotKey.register(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey))
            let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == HotkeyManager.escapeKeyCode { self?.onEscape?() }
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == HotkeyManager.escapeKeyCode else { return event }
                self?.onEscape?()
                return nil
            }
            escapeMonitors = [global, local].compactMap { $0 }
        } else {
            escapeHotKey.unregister()
            escapeOptionHotKey.unregister()
            for monitor in escapeMonitors {
                NSEvent.removeMonitor(monitor)
            }
            escapeMonitors = []
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let functionDown = event.modifierFlags.contains(.function)
            if let edge = fnTracker.handle(keyCode: event.keyCode, functionFlag: functionDown) {
                if edge == .pressed { chorded = false }
                onEdge?(edge)
            }
        case .keyDown:
            // Échap a son propre traitement (annulation avec message « Dictée annulée. »).
            guard fnTracker.isDown, event.keyCode != Self.escapeKeyCode else { break }
            chorded = true
            onFnChord?()
        default:
            break
        }
    }
}
