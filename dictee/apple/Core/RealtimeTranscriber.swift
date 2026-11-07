import Foundation

/// Session de transcription en continu (SPEC §2 ter) : WebSocket ouvert à l'appui, audio envoyé au fil de l'eau,
/// texte final demandé au relâchement. Toute erreur remonte à l'appelant, qui retombe sur l'envoi du fichier.
/// `append(pcm:)` peut être appelé depuis le thread audio ; le reste se fait sur une file série.
final class RealtimeTranscriber: @unchecked Sendable {
    enum Failure: LocalizedError {
        case notConfigured
        case server(String)
        case closed
        case timeout

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Transcription en continu indisponible pour ce fournisseur."
            case let .server(message): return message
            case .closed: return "Connexion de transcription fermée."
            case .timeout: return "Texte final non reçu à temps."
            }
        }
    }

    /// Délai maximal entre le relâchement et le texte final (SPEC §2 ter : repli fichier au-delà).
    static let completionTimeout: TimeInterval = 10

    let provider: TranscriptionProvider
    /// Fréquence PCM attendue par le fournisseur, pour l'enregistreur.
    var sampleRate: Double { RealtimeProtocol.sampleRate(for: provider) }

    private let settings: TranscriptionSettings
    private let apiKey: String
    private let session: URLSession
    private let queue = DispatchQueue(label: "dictee.realtime")

    private var task: URLSessionWebSocketTask?
    private var ready = false
    private var failed: Error?
    /// Audio reçu avant `session.updated`, envoyé dès que la session est prête.
    private var buffered: [Data] = []
    private var deltas: [String] = []
    private var completed: String?
    private var completion: CheckedContinuation<String, Error>?
    private var timeoutWork: DispatchWorkItem?

    init(provider: TranscriptionProvider, settings: TranscriptionSettings, apiKey: String, session: URLSession = .shared) {
        self.provider = provider
        self.settings = settings
        self.apiKey = apiKey
        self.session = session
    }

    /// Ouvre la connexion et envoie la configuration. Ne bloque pas : l'audio est mis en tampon jusqu'à `session.updated`.
    func start() throws {
        guard RealtimeProtocol.supports(provider), let url = RealtimeProtocol.url(for: provider, settings: settings) else {
            throw Failure.notConfigured
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        for (name, value) in RealtimeProtocol.headers(for: provider, apiKey: apiKey) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        send(RealtimeProtocol.sessionUpdate(for: provider, settings: settings))
        receiveLoop(task)
    }

    /// Un morceau PCM16 (thread audio) : envoyé tout de suite si la session est prête, sinon gardé.
    func append(pcm: Data) {
        guard !pcm.isEmpty else { return }
        queue.async { [self] in
            guard failed == nil, task != nil else { return }
            if ready {
                sendLocked(RealtimeProtocol.append(for: provider, pcm: pcm))
            } else {
                buffered.append(pcm)
            }
        }
    }

    /// Relâchement : demande le texte final et l'attend (au plus `completionTimeout`).
    func finish() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let failed {
                    continuation.resume(throwing: failed)
                    return
                }
                guard task != nil else {
                    continuation.resume(throwing: Failure.closed)
                    return
                }
                if let completed {
                    continuation.resume(returning: RealtimeProtocol.finalText(completed: completed, deltas: deltas))
                    return
                }
                completion = continuation
                if ready {
                    sendLocked(RealtimeProtocol.end(for: provider))
                } else {
                    // La session n'est pas encore prête : la fin partira juste après le tampon.
                    buffered.append(Data())
                }
                let work = DispatchWorkItem { [weak self] in self?.fail(Failure.timeout) }
                timeoutWork = work
                queue.asyncAfter(deadline: .now() + Self.completionTimeout, execute: work)
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            timeoutWork?.cancel()
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            if let completion {
                self.completion = nil
                completion.resume(throwing: CancellationError())
            }
        }
    }

    // MARK: - Interne (sur `queue`)

    private func send(_ data: Data) {
        queue.async { [self] in sendLocked(data) }
    }

    private func sendLocked(_ data: Data) {
        guard let task, let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            if let error { self?.fail(error) }
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                self.fail(error)
            case let .success(message):
                let data: Data
                switch message {
                case let .string(text): data = Data(text.utf8)
                case let .data(bytes): data = bytes
                @unknown default: data = Data()
                }
                self.handle(RealtimeProtocol.parse(data, provider: self.provider))
                self.receiveLoop(task)
            }
        }
    }

    private func handle(_ event: RealtimeProtocol.Event) {
        queue.async { [self] in
            switch event {
            case .ready:
                ready = true
                for chunk in buffered {
                    // Un morceau vide marque la demande de fin arrivée avant que la session soit prête.
                    sendLocked(chunk.isEmpty ? RealtimeProtocol.end(for: provider) : RealtimeProtocol.append(for: provider, pcm: chunk))
                }
                buffered = []
            case let .delta(text):
                deltas.append(text)
            case let .completed(text):
                completed = text
                timeoutWork?.cancel()
                if let completion {
                    self.completion = nil
                    completion.resume(returning: RealtimeProtocol.finalText(completed: text, deltas: deltas))
                    task?.cancel(with: .normalClosure, reason: nil)
                    task = nil
                }
            case let .error(message):
                fail(Failure.server(message))
            case .ignored:
                break
            }
        }
    }

    private func fail(_ error: Error) {
        queue.async { [self] in
            guard failed == nil else { return }
            failed = error
            timeoutWork?.cancel()
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            if let completion {
                self.completion = nil
                completion.resume(throwing: error)
            }
        }
    }
}
