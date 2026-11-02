import AVFoundation

/// Micro → fichier WAV 16 kHz mono (via BufferRecorder).
/// Un AVAudioEngine neuf à chaque dictée : le micro par défaut peut changer entre deux dictées,
/// et le voyant orange du micro ne reste pas allumé hors enregistrement. Pas d'AVAudioSession sur macOS.
@MainActor
final class AudioCapture {
    enum CaptureError: LocalizedError {
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .noMicrophone: return "Aucun micro disponible."
            }
        }
    }

    /// Appelé en dernier recours, si le micro ne redémarre pas après un changement de périphérique.
    var onConfigurationChange: (() -> Void)?

    /// Plafond de redémarrages pendant une dictée (évite une boucle si la configuration change sans cesse).
    private static let maxRestarts = 3

    private let recorder = BufferRecorder()
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var restarts = 0

    /// Niveau sonore récent (0 à 1).
    var level: Float { recorder.level }

    func start() throws {
        stopEngine()
        restarts = 0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictee-\(UUID().uuidString).wav")

        try recorder.begin(url: url)
        do {
            try startEngine()
        } catch {
            recorder.cancel()
            throw error
        }
    }

    /// Arrête le micro et renvoie le fichier enregistré et sa durée.
    func finish() -> (url: URL, duration: TimeInterval)? {
        stopEngine()
        return recorder.finish()
    }

    /// Arrête le micro et supprime le fichier.
    func cancel() {
        stopEngine()
        recorder.cancel()
    }

    /// Moteur neuf sur le micro par défaut du moment ; le fichier en cours reste ouvert.
    private func startEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noMicrophone
        }

        // Posé avant start() : avec des AirPods, le passage en profil micro (HFP) change la configuration
        // juste après le démarrage.
        let engineID = ObjectIdentifier(engine)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange(engineID: engineID) }
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.makeTapBlock(recorder))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            removeConfigurationObserver()
            throw error
        }
        self.engine = engine
    }

    /// Le moteur s'arrête de lui-même quand le périphérique change (casque branché, AirPods, micro débranché) :
    /// on repart sur le nouveau micro, dans le même fichier (BufferRecorder s'adapte au nouveau format).
    private func handleConfigurationChange(engineID: ObjectIdentifier) {
        guard let engine, ObjectIdentifier(engine) == engineID else { return } // notification d'un ancien moteur
        stopEngine()
        restarts += 1
        do {
            guard restarts <= Self.maxRestarts else { throw CaptureError.noMicrophone }
            try startEngine()
        } catch {
            onConfigurationChange?()
        }
    }

    private func stopEngine() {
        removeConfigurationObserver()
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func removeConfigurationObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    /// Bloc créé hors du MainActor : il s'exécute sur le thread audio. Le créer dans une méthode
    /// @MainActor ferait planter l'app (vérification d'isolation des compilateurs Swift récents).
    nonisolated private static func makeTapBlock(_ recorder: BufferRecorder) -> AVAudioNodeTapBlock {
        { buffer, _ in recorder.append(buffer) }
    }
}
