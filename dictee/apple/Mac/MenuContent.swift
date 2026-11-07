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
            Menu(controller.lastLatency.map { "Dernière transcription · \(Self.latencyLabel($0))" } ?? "Dernière transcription") {
                Text(Self.preview(of: controller.lastTranscript))
                if let note = controller.lastStreamingNote {
                    Text(Self.preview(of: note, limit: 400))
                }
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

    /// Durée relâchement → texte, en secondes avec une décimale (SPEC §2 ter).
    nonisolated static func latencyLabel(_ seconds: TimeInterval) -> String {
        String(format: "%.1f s", locale: Locale(identifier: "fr_FR"), seconds)
    }

    /// Début du texte, sur une ligne, pour le menu.
    nonisolated static func preview(of text: String, limit: Int = 60) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit)) + "…"
    }
}
