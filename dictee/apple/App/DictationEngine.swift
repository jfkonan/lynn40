import AVFoundation
import UIKit

/// Cœur de l'app : garde une session audio active en arrière-plan, enregistre à la demande
/// du clavier, envoie l'audio à OpenAI et dépose le texte dans l'App Group.
///
/// Pourquoi une session permanente : iOS interdit le micro aux claviers et ne laisse pas une app
/// en arrière-plan *démarrer* le micro. On démarre donc le moteur audio une fois (app au premier plan),
/// puis on le laisse tourner : les tampons sont ignorés sauf pendant un enregistrement.
@MainActor
final class DictationEngine: ObservableObject {
    static let shared = DictationEngine()

    @Published private(set) var sessionActive = false
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastError: String?
    @Published private(set) var inputLevel: Float = 0
    /// Vrai quand la session vient d'être lancée depuis le clavier : l'écran invite à revenir en arrière.
    @Published var launchedFromKeyboard = false

    /// Durée maximale d'un enregistrement (limite de 25 Mo d'OpenAI).
    static let maxRecordingDuration: TimeInterval = 12 * 60

    private let store = SharedStore.shared
    private let audioEngine = AVAudioEngine()
    private let recorder = BufferRecorder()
    private var heartbeatTimer: Timer?
    private var maxDurationTimer: Timer?
    private var sessionDeadline = Date.distantPast
    private var transcriptionTask: Task<Void, Never>?
    private var signalTokens: [UUID] = []
    private var systemObservers: [NSObjectProtocol] = []

    private init() {
        let notifier = DarwinNotifier.shared
        signalTokens = [
            notifier.observe(.startRecording) { [weak self] in self?.startRecording() },
            notifier.observe(.stopRecording) { [weak self] in self?.stopRecording() },
            notifier.observe(.cancelRecording) { [weak self] in self?.cancelRecording() },
        ]

        let center = NotificationCenter.default
        systemObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.handleInterruption(rawType: rawType) }
        })
        systemObservers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        })
        systemObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.endSession(reason: "Services audio réinitialisés par iOS.") }
        })

        // Un état « recording » laissé par un ancien processus ne doit pas bloquer le clavier.
        store.sessionExpiresAt = nil
        publish(.idle, error: nil)
    }

    // MARK: - Lien depuis le clavier (dictee://start)

    func handle(url: URL) {
        guard url.scheme == "dictee" else { return }
        switch url.host {
        case "start":
            launchedFromKeyboard = true
            Task { await startSessionIfAllowed() }
        default:
            break
        }
    }

    // MARK: - Session

    func startSessionIfAllowed() async {
        guard await requestMicrophonePermission() else {
            publish(.error, error: "Accès au micro refusé. Autorisez-le dans Réglages > Dictée.")
            return
        }
        do {
            try startSession()
        } catch {
            publish(.error, error: "Impossible de démarrer l'audio : \(error.localizedDescription)")
        }
    }

    func startSession() throws {
        if sessionActive {
            extendSession()
            return
        }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Dictee", code: 1, userInfo: [NSLocalizedDescriptionKey: "Aucun micro disponible."])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.makeTapBlock(recorder))
        audioEngine.prepare()
        try audioEngine.start()

        sessionActive = true
        extendSession()
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
        heartbeat()
        DarwinNotifier.shared.post(.stateChanged)
    }

    func endSession(reason: String? = nil) {
        if recorder.isRecording { recorder.cancel() }
        maxDurationTimer?.invalidate()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
        launchedFromKeyboard = false
        inputLevel = 0
        store.sessionExpiresAt = nil
        if state != .transcribing {
            publish(reason == nil ? .idle : .error, error: reason)
        } else {
            DarwinNotifier.shared.post(.stateChanged)
        }
    }

    /// Repousse la fin automatique de session (chaque dictée relance le compteur).
    private func extendSession() {
        sessionDeadline = Date().addingTimeInterval(TimeInterval(store.sessionMinutes * 60))
    }

    private func heartbeat() {
        guard sessionActive else { return }
        inputLevel = recorder.level
        if state == .idle, Date() > sessionDeadline {
            endSession()
            return
        }
        // Le clavier considère la session morte si ce délai n'est plus rafraîchi.
        store.sessionExpiresAt = Date().addingTimeInterval(6)
    }

    // MARK: - Enregistrement

    func startRecording() {
        guard sessionActive else {
            publish(.error, error: "Session inactive : ouvrez l'app Dictée.")
            return
        }
        guard state == .idle || state == .error else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictee-\(UUID().uuidString).wav")
        do {
            try recorder.begin(url: url)
        } catch {
            publish(.error, error: "Impossible de créer le fichier audio : \(error.localizedDescription)")
            return
        }
        extendSession()
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stopRecording() }
        }
        publish(.recording, error: nil)
    }

    func stopRecording() {
        guard state == .recording else { return }
        maxDurationTimer?.invalidate()
        guard let result = recorder.finish() else {
            publish(.error, error: "Aucun audio enregistré.")
            return
        }
        guard result.duration >= 0.3 else {
            try? FileManager.default.removeItem(at: result.url)
            publish(.idle, error: nil)
            return
        }
        publish(.transcribing, error: nil)
        transcriptionTask = Task { [weak self] in
            await self?.transcribe(fileURL: result.url)
        }
    }

    func cancelRecording() {
        maxDurationTimer?.invalidate()
        recorder.cancel()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        publish(.idle, error: nil)
    }

    private func transcribe(fileURL: URL) async {
        // Laisse le temps de finir l'appel réseau si iOS veut suspendre l'app.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "dictee.transcription")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }

        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            publish(.error, error: OpenAIClient.ClientError.missingAPIKey.errorDescription)
            return
        }
        let client = OpenAIClient(apiKey: apiKey)

        do {
            var text = try await client.transcribe(
                audioURL: fileURL,
                model: store.model,
                language: store.language,
                prompt: store.vocabulary
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            if store.cleanupEnabled, !text.isEmpty {
                // En cas d'échec du nettoyage, on garde le texte brut plutôt que de tout perdre.
                if let cleaned = try? await client.cleanUp(text: text, model: store.cleanupModel, vocabulary: store.vocabulary),
                   !cleaned.isEmpty {
                    text = cleaned
                }
            }
            try Task.checkCancellation()

            guard !text.isEmpty else {
                publish(.error, error: "Aucune parole détectée.")
                return
            }
            store.latestTranscript = Transcript(id: UUID().uuidString, text: text, createdAt: Date())
            lastTranscript = text
            publish(.idle, error: nil)
            DarwinNotifier.shared.post(.transcriptReady)
        } catch is CancellationError {
            publish(.idle, error: nil)
        } catch let error as URLError where error.code == .cancelled {
            publish(.idle, error: nil)
        } catch {
            publish(.error, error: error.localizedDescription)
        }
    }

    // MARK: - Événements système

    private func handleInterruption(rawType: UInt?) {
        guard let rawType, AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
        // Appel téléphonique, Siri… : on garde ce qui a été dicté puis on coupe la session.
        if state == .recording { stopRecording() }
        endSession(reason: "Session interrompue par iOS (appel, Siri…). Relancez-la depuis le clavier.")
    }

    private func handleConfigurationChange() {
        // Changement de micro (écouteurs branchés…) : on relance le moteur avec le nouveau format.
        guard sessionActive else { return }
        if state == .recording { stopRecording() }
        let pendingTranscription = state == .transcribing
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        sessionActive = false
        do {
            try startSession()
            if !pendingTranscription, state == .error { publish(.idle, error: nil) }
        } catch {
            endSession(reason: "Le micro a changé et l'audio n'a pas pu redémarrer.")
        }
    }

    // MARK: - Utilitaires

    private func publish(_ newState: DictationState, error: String?) {
        state = newState
        lastError = error
        store.state = newState
        store.errorMessage = error
        DarwinNotifier.shared.post(.stateChanged)
    }

    /// Hors MainActor pour la même raison que `makeTapBlock` : iOS rappelle sur un thread quelconque.
    nonisolated private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
    }

    /// Bloc créé hors du MainActor : il s'exécute sur le thread audio. Le créer dans une méthode
    /// @MainActor ferait planter l'app (vérification d'isolation des compilateurs Swift récents).
    nonisolated private static func makeTapBlock(_ recorder: BufferRecorder) -> AVAudioNodeTapBlock {
        { buffer, _ in recorder.append(buffer) }
    }
}
