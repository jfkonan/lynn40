import AppKit
import SwiftUI

/// Contenu de la pastille flottante (SPEC §6).
enum OverlayPhase: Equatable {
    case listening
    case transcribing
    case info(String)
    case error(String)
}

/// Niveau du micro, mis à jour ~20 fois par seconde pendant l'écoute.
final class OverlayLevel: ObservableObject {
    @Published var value: Float = 0
}

/// Fenêtre qui ne devient jamais clé : la pastille ne vole pas le focus de l'app où l'on dicte.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    let level: OverlayLevel
    private let panel: OverlayPanel
    private let hostingView: NSHostingView<OverlayView>
    /// Incrémenté à chaque affichage : un masquage différé obsolète ne fait rien.
    private var generation = 0

    init() {
        let level = OverlayLevel()
        self.level = level
        hostingView = NSHostingView(rootView: OverlayView(phase: .listening, level: level))
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
    }

    /// Affiche la pastille ; `autoHideAfter` la masque après ce délai (messages et erreurs).
    func show(_ phase: OverlayPhase, autoHideAfter delay: TimeInterval? = nil) {
        generation += 1
        let current = generation
        hostingView.rootView = OverlayView(phase: phase, level: level)
        place(size: hostingView.fittingSize)
        panel.orderFrontRegardless()

        guard let delay else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.generation == current else { return }
            self.hide()
        }
    }

    func hide() {
        generation += 1
        level.value = 0
        panel.orderOut(nil)
    }

    /// En bas au centre de l'écran où se trouve le pointeur.
    private func place(size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: (frame.midX - size.width / 2).rounded(), y: frame.minY + 48)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

struct OverlayView: View {
    let phase: OverlayPhase
    @ObservedObject var level: OverlayLevel

    var body: some View {
        HStack(spacing: 10) {
            switch phase {
            case .listening:
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                Text("Écoute…")
                LevelBars(level: level.value)
            case .transcribing:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("Transcription…")
            case let .info(message):
                Image(systemName: "doc.on.clipboard")
                messageText(message)
            case let .error(message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                messageText(message)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.8))
        )
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    /// Largeur fixe pour que la hauteur calculée tienne compte du retour à la ligne.
    private func messageText(_ message: String) -> some View {
        Text(message)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .frame(width: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Indicateur de niveau : cinq barres qui s'allument selon le volume.
struct LevelBars: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(level > Float(index) / 5 ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 3, height: CGFloat(6 + (index % 3) * 4))
            }
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
