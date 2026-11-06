import AppKit
import SwiftUI

/// Fenêtre de réglages gérée à la main : la scène `Settings` de SwiftUI est peu fiable
/// dans une app sans icône dans le Dock (LSUIElement).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    /// App au premier plan avant l'ouverture des réglages, réactivée à leur fermeture.
    private var previousApp: NSRunningApplication?

    private init() {}

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        let window = self.window ?? makeWindow()
        self.window = window
        bringToFront(window)
        // Le menu de la barre des menus se ferme après l'action et macOS rend alors la main à l'app
        // précédente : on remet la fenêtre devant une fois le menu refermé. Pas si l'utilisateur l'a déjà
        // fermée entre-temps : la rouvrir laisserait Dictée active (voir `returnFocusToPreviousApp`).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak window] in
            guard let self, let window, window.isVisible else { return }
            self.bringToFront(window)
        }
    }

    private func bringToFront(_ window: NSWindow) {
        // Une app LSUIElement n'est jamais active d'elle-même : sans ça, la fenêtre reste derrière.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(controller: DictationController.shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Réglages de Dictée"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.returnFocusToPreviousApp() }
        }
        return window
    }

    /// App LSUIElement : sans fenêtre, Dictée resterait l'app active et le ⌘V simulé n'atteindrait pas
    /// l'app où l'on dicte. On rend donc la main à l'app d'avant.
    private func returnFocusToPreviousApp() {
        guard NSApp.isActive, let previousApp, !previousApp.isTerminated else { return }
        previousApp.activate(options: [])
    }
}
