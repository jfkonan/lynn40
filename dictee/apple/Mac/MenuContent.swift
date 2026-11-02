import AppKit
import SwiftUI

/// Menu de l'icône de la barre des menus (SPEC §6).
struct MenuContent: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Text(controller.statusLine)

        Divider()

        if controller.lastTranscript.isEmpty {
            Text("Dernière transcription : aucune")
        } else {
            Menu("Dernière transcription") {
                Text(Self.preview(of: controller.lastTranscript))
                Divider()
                Button("Copier") { controller.copyLastTranscript() }
            }
        }

        Divider()

        Button("Réglages…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quitter") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Début du texte, sur une ligne, pour le menu.
    nonisolated static func preview(of text: String, limit: Int = 60) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit)) + "…"
    }
}
