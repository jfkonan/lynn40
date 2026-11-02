import Foundation

/// Logique du clavier : suit l'état de l'app via l'App Group et pilote la dictée par signaux Darwin.
@MainActor
final class KeyboardModel: ObservableObject {
    enum Phase: Equatable {
        case noFullAccess
        case needsSession
        case ready
        case recording
        case transcribing
        case error(String)
    }

    @Published private(set) var phase: Phase = .needsSession
    @Published private(set) var hint: String?
    @Published private(set) var showsGlobeKey = true

    private weak var controller: KeyboardViewController?
    private let store = SharedStore.shared
    private var tokens: [UUID] = []
    private var refreshTimer: Timer?
    private var startTimeout: DispatchWorkItem?

    init(controller: KeyboardViewController) {
        self.controller = controller
    }

    deinit {
        let notifier = DarwinNotifier.shared
        tokens.forEach { notifier.remove($0) }
    }

    // MARK: - Cycle de vie

    func appear() {
        showsGlobeKey = controller?.showsGlobeKey ?? true
        if tokens.isEmpty {
            let notifier = DarwinNotifier.shared
            tokens = [
                notifier.observe(.stateChanged) { [weak self] in self?.refresh() },
                notifier.observe(.transcriptReady) { [weak self] in self?.insertPendingTranscript() },
            ]
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        // Si une transcription est arrivée pendant que le clavier était masqué (récente uniquement).
        insertPendingTranscript()
    }

    func disappear() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if phase == .recording {
            DarwinNotifier.shared.post(.cancelRecording)
        }
    }

    // MARK: - Actions

    func micTapped() {
        refresh()
        switch phase {
        case .noFullAccess:
            hint = "Activez « Autoriser l'accès complet » : Réglages > Général > Clavier > Claviers > Dictée."
        case .needsSession:
            openApp()
        case .ready, .error:
            hint = nil
            phase = .recording
            DarwinNotifier.shared.post(.startRecording)
            armStartTimeout()
        case .recording:
            phase = .transcribing
            DarwinNotifier.shared.post(.stopRecording)
        case .transcribing:
            break
        }
    }

    func cancelTapped() {
        DarwinNotifier.shared.post(.cancelRecording)
    }

    func insert(_ text: String) { controller?.insert(text) }
    func deleteBackward() { controller?.deleteBackward() }
    func nextKeyboard() { controller?.advanceToNextInputMode() }

    // MARK: - Synchronisation avec l'app

    func refresh() {
        guard let controller else { return }
        guard controller.hasFullAccess else {
            phase = .noFullAccess
            return
        }
        guard store.isSessionAlive() else {
            // L'app peut finir une transcription même après la fin de session.
            phase = store.state == .transcribing ? .transcribing : .needsSession
            return
        }
        switch store.state {
        case .idle:
            if phase != .recording || startTimeout == nil { phase = .ready }
        case .recording:
            startTimeout?.cancel()
            startTimeout = nil
            phase = .recording
        case .transcribing:
            phase = .transcribing
        case .error:
            if phase != .recording || startTimeout == nil {
                phase = .error(store.errorMessage ?? "Erreur inconnue.")
            }
        }
    }

    private func insertPendingTranscript() {
        refresh()
        guard let transcript = store.unconsumedTranscript() else { return }
        store.markConsumed(transcript)
        controller?.insertDictation(transcript.text)
    }

    private func openApp() {
        guard let url = URL(string: "dictee://start"), controller?.openContainingApp(url) == true else {
            hint = "Ouvrez l'app Dictée et touchez « Démarrer la session »."
            return
        }
        hint = "Après l'ouverture, revenez ici avec « ‹ » en haut à gauche."
    }

    /// Si l'app ne confirme pas le début d'enregistrement, c'est qu'elle ne tourne plus.
    private func armStartTimeout() {
        startTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startTimeout = nil
            if self.store.state != .recording {
                self.phase = .needsSession
                self.hint = "L'app Dictée ne répond pas. Touchez le micro pour relancer la session."
            }
        }
        startTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
