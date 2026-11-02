import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 10) {
            statusLine
                .frame(height: 34)

            HStack(spacing: 6) {
                ForEach([",", ".", "?", "!", "'", "-"], id: \.self) { symbol in
                    KeyButton(label: Text(symbol)) { model.insert(symbol) }
                }
            }

            ZStack {
                micButton
                if model.phase == .recording {
                    HStack {
                        Spacer()
                        Button(action: model.cancelTapped) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                        }
                        .accessibilityLabel("Annuler la dictée")
                        .padding(.trailing, 24)
                    }
                }
            }
            .frame(height: 96)

            HStack(spacing: 6) {
                if model.showsGlobeKey {
                    KeyButton(label: Image(systemName: "globe")) { model.nextKeyboard() }
                        .frame(width: 48)
                        .accessibilityLabel("Clavier suivant")
                }
                KeyButton(label: Text("espace")) { model.insert(" ") }
                RepeatingKeyButton(label: Image(systemName: "delete.left")) { model.deleteBackward() }
                    .frame(width: 56)
                    .accessibilityLabel("Effacer")
                KeyButton(label: Image(systemName: "return")) { model.insert("\n") }
                    .frame(width: 56)
                    .accessibilityLabel("Retour à la ligne")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    // MARK: - Éléments

    private var statusLine: some View {
        Text(statusText)
            .font(.footnote)
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }

    private var micButton: some View {
        Button(action: model.micTapped) {
            ZStack {
                Circle()
                    .fill(micColor)
                    .frame(width: 84, height: 84)
                if model.phase == .transcribing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: micSymbol)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(micAccessibilityLabel)
    }

    private var statusText: String {
        if let hint = model.hint { return hint }
        switch model.phase {
        case .noFullAccess: return "Accès complet requis : touchez le micro pour savoir comment l'activer."
        case .needsSession: return "Touchez le micro pour démarrer une session Dictée."
        case .ready: return "Touchez pour dicter."
        case .recording: return "Je vous écoute… Touchez pour terminer."
        case .transcribing: return "Transcription…"
        case let .error(message): return message
        }
    }

    private var isError: Bool {
        if case .error = model.phase { return true }
        return false
    }

    private var micColor: Color {
        switch model.phase {
        case .recording: return .red
        case .transcribing: return .orange
        case .noFullAccess, .needsSession: return .gray
        case .ready, .error: return .accentColor
        }
    }

    private var micSymbol: String {
        switch model.phase {
        case .recording: return "stop.fill"
        case .needsSession: return "arrow.up.forward.app"
        case .noFullAccess: return "lock.fill"
        default: return "mic.fill"
        }
    }

    private var micAccessibilityLabel: String {
        switch model.phase {
        case .recording: return "Terminer la dictée"
        case .needsSession: return "Démarrer une session dans l'app Dictée"
        default: return "Dicter"
        }
    }
}

/// Touche simple au style clavier iOS.
private struct KeyButton<Label: View>: View {
    let label: Label
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 18))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground)))
                .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1)
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Touche qui se répète tant qu'on la maintient (effacement).
private struct RepeatingKeyButton<Label: View>: View {
    let label: Label
    let action: () -> Void

    @State private var timer: Timer?
    @State private var pressed = false

    var body: some View {
        label
            .font(.system(size: 18))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(uiColor: pressed ? UIColor.systemGray4 : UIColor.systemBackground)))
            .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in action() }
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        timer?.invalidate()
                        timer = nil
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}
