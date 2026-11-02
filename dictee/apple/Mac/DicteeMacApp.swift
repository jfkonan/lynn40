import AppKit
import SwiftUI

/// App de barre des menus (pas d'icône dans le Dock : LSUIElement dans l'Info.plist).
@main
struct DicteeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = DictationController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: controller.state.menuBarSymbol)
                .accessibilityLabel("Dictée")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hôte des tests unitaires : ni raccourcis, ni fenêtre, ni demande d'autorisation.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        DictationController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // « Quitter » pendant l'écoute ou la transcription : l'audio ne doit pas rester sur le disque.
        DictationController.shared.shutdown()
    }
}
