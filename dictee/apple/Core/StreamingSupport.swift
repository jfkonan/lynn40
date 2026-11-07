import Foundation

/// Transcription en continu côté moteurs iOS et macOS (SPEC §2 ter) : décide si on diffuse, relie l'enregistreur
/// à la session, et retombe sur l'envoi du fichier (SPEC §2.2) à la moindre erreur.
enum StreamingSupport {
    /// Session pré-ouverte, prête avant l'appui (SPEC §2 ter : la poignée de main prend 1 à 1,5 s).
    private static var warm: RealtimeTranscriber?
    private static let warmLock = NSLock()

    /// Session en continu pour l'enregistrement qui commence : la session pré-ouverte si elle est vivante et que les
    /// réglages n'ont pas changé, sinon une nouvelle. `nil` : réglage désactivé, fournisseur sans protocole, clé absente
    /// ou connexion impossible. Dans ce dernier cas, le fichier seul fera le travail.
    static func makeTranscriber(store: SharedStore) -> RealtimeTranscriber? {
        guard store.streamingEnabled else {
            discardWarm()
            return nil
        }
        let provider = store.provider
        guard RealtimeProtocol.supports(provider),
              let apiKey = KeychainStore.loadAllKeys().key(for: provider) else {
            discardWarm()
            return nil
        }
        let settings = store.transcriptionSettings
        warmLock.lock()
        let candidate = warm
        warm = nil
        warmLock.unlock()
        if let candidate {
            let configuration = candidate.configuration
            if candidate.isAlive, configuration.provider == provider, configuration.settings == settings, configuration.apiKey == apiKey {
                candidate.markPressed()
                return candidate
            }
            candidate.cancel()
        }
        return open(provider: provider, settings: settings, apiKey: apiKey)
    }

    /// Ouvre à l'avance la session de la prochaine dictée (au démarrage et après chaque dictée). Sans effet si le
    /// continu est inactif ; remplace une session pré-ouverte dont les réglages ont changé.
    static func prepare(store: SharedStore) {
        guard store.streamingEnabled else {
            discardWarm()
            return
        }
        let provider = store.provider
        guard RealtimeProtocol.supports(provider),
              let apiKey = KeychainStore.loadAllKeys().key(for: provider) else {
            discardWarm()
            return
        }
        let settings = store.transcriptionSettings
        warmLock.lock()
        if let existing = warm {
            let configuration = existing.configuration
            if existing.isAlive, configuration.provider == provider, configuration.settings == settings, configuration.apiKey == apiKey {
                warmLock.unlock()
                return
            }
            existing.cancel()
            warm = nil
        }
        warmLock.unlock()
        guard let fresh = open(provider: provider, settings: settings, apiKey: apiKey) else { return }
        warmLock.lock()
        warm = fresh
        warmLock.unlock()
    }

    /// Ferme la session pré-ouverte (fin de session iOS, fermeture de l'app Mac).
    static func discardWarm() {
        warmLock.lock()
        let existing = warm
        warm = nil
        warmLock.unlock()
        existing?.cancel()
    }

    private static func open(provider: TranscriptionProvider, settings: TranscriptionSettings, apiKey: String) -> RealtimeTranscriber? {
        let transcriber = RealtimeTranscriber(provider: provider, settings: settings, apiKey: apiKey)
        do {
            try transcriber.start()
            return transcriber
        } catch {
            return nil
        }
    }

    /// Flux PCM de l'enregistreur vers la session.
    static func stream(for transcriber: RealtimeTranscriber) -> BufferRecorder.Stream {
        BufferRecorder.Stream(sampleRate: transcriber.sampleRate) { pcm in transcriber.append(pcm: pcm) }
    }

    struct Result {
        let text: String
        /// Diagnostic affiché sous la dernière transcription : repères de temps du continu, ou raison du repli fichier.
        let fallbackReason: String?
    }

    /// Texte brut : celui de la session en continu si elle aboutit, sinon l'envoi du fichier (sans message d'erreur
    /// pour le repli, SPEC §2 ter ; la raison est gardée pour l'affichage). Une annulation remonte telle quelle.
    static func rawText(
        streamer: RealtimeTranscriber?,
        provider: TranscriptionProvider,
        audioURL: URL,
        settings: TranscriptionSettings,
        keys: ProviderKeys
    ) async throws -> Result {
        // Pas de session : réglage désactivé, fournisseur sans protocole ou clé absente. Ce n'est pas un repli,
        // donc pas de raison affichée.
        var reason: String?
        if let streamer {
            do {
                let text = try await streamer.finish().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return Result(text: text, fallbackReason: "continu : " + streamer.timingSummary) }
                reason = "texte vide en continu (" + streamer.timingSummary + ")"
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                reason = "repli fichier : " + TranscriptionService.redactKeys(error.localizedDescription, apiKey: keys.key(for: provider))
                    + " (" + streamer.timingSummary + ")"
            }
            try Task.checkCancellation()
        }
        let text = try await TranscriptionService.transcribe(
            provider: provider,
            audioURL: audioURL,
            settings: settings,
            keys: keys
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(text: text, fallbackReason: reason)
    }
}
