import AVFoundation

/// Reçoit les tampons du micro (thread audio) et, pendant un enregistrement,
/// les convertit en 16 kHz mono et les écrit dans un fichier WAV.
/// 16 kHz mono 16 bits = 32 Ko/s, soit environ 13 min sous la limite de 25 Mo d'OpenAI.
/// En parallèle, si un `stream` est fourni, chaque tampon est aussi converti en PCM16 à la fréquence demandée
/// et transmis au flux de transcription en continu (SPEC §2 ter) ; le fichier reste le repli.
final class BufferRecorder: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    /// Destination des morceaux PCM16 (little-endian, mono, sans en-tête), appelée sur le thread audio.
    struct Stream {
        let sampleRate: Double
        let sink: @Sendable (Data) -> Void
    }

    private var stream: Stream?
    private var streamFormat: AVAudioFormat?
    private var streamConverter: AVAudioConverter?
    private var streamConverterInputFormat: AVAudioFormat?

    private let lock = NSLock()
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: BufferRecorder.sampleRate,
        channels: 1,
        interleaved: false
    )!
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var framesWritten: AVAudioFramePosition = 0
    private var currentLevel: Float = 0

    /// Niveau sonore récent (0 à 1), pour l'affichage.
    var level: Float {
        lock.lock(); defer { lock.unlock() }
        return currentLevel
    }

    var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return file != nil
    }

    func begin(url: URL, stream: Stream? = nil) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: BufferRecorder.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        try? FileManager.default.removeItem(at: url)
        let newFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.lock()
        file = newFile
        fileURL = url
        framesWritten = 0
        self.stream = stream
        streamFormat = stream.flatMap {
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: $0.sampleRate, channels: 1, interleaved: true)
        }
        streamConverter = nil
        streamConverterInputFormat = nil
        lock.unlock()
    }

    /// Appelé depuis le thread audio pour chaque tampon du micro.
    func append(_ buffer: AVAudioPCMBuffer) {
        let level = Self.rmsLevel(of: buffer)

        lock.lock()
        defer { lock.unlock() }
        currentLevel = level
        guard let file else { return }

        if converter == nil || converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converterInputFormat = buffer.format
        }
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, output.frameLength > 0 else { return }
        do {
            try file.write(from: output)
            framesWritten += AVAudioFramePosition(output.frameLength)
        } catch {
            // Un tampon perdu ne doit pas interrompre la dictée.
        }
        streamChunk(from: buffer)
    }

    /// Convertit le tampon du micro en PCM16 à la fréquence du flux et le transmet. Sous `lock`.
    private func streamChunk(from buffer: AVAudioPCMBuffer) {
        guard let stream, let streamFormat else { return }
        if streamConverter == nil || streamConverterInputFormat != buffer.format {
            streamConverter = AVAudioConverter(from: buffer.format, to: streamFormat)
            streamConverterInputFormat = buffer.format
        }
        guard let streamConverter else { return }
        let ratio = streamFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: streamFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var conversionError: NSError?
        let status = streamConverter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return }
        let data = Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
        stream.sink(data)
    }

    /// Termine l'enregistrement et renvoie le fichier et sa durée en secondes.
    func finish() -> (url: URL, duration: TimeInterval)? {
        lock.lock()
        defer { lock.unlock() }
        guard file != nil, let url = fileURL else { return nil }
        file = nil // libérer l'AVAudioFile ferme le fichier
        fileURL = nil
        converter?.reset()
        stream = nil
        streamConverter = nil
        return (url, Double(framesWritten) / BufferRecorder.sampleRate)
    }

    func cancel() {
        if let result = finish() {
            try? FileManager.default.removeItem(at: result.url)
        }
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        return min(1, rms * 8)
    }
}
