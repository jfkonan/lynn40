import Foundation

/// Transcription en continu côté moteurs iOS et macOS (SPEC §2 ter) : décide si on diffuse, relie l'enregistreur
/// à la session, et retombe sur l'envoi du fichier (SPEC §2.2) à la moindre erreur.
enum StreamingSupport {
    /// Session en continu pour l'enregistrement qui commence, ou `nil` : réglage désactivé, fournisseur sans
    /// protocole, clé absente ou connexion impossible. Dans ce dernier cas, le fichier seul fera le travail.
    static func makeTranscriber(store: SharedStore) -> RealtimeTranscriber? {
        guard store.streamingEnabled else { return nil }
        let provider = store.provider
        guard RealtimeProtocol.supports(provider),
              let apiKey = KeychainStore.loadAllKeys().key(for: provider) else { return nil }
        let transcriber = RealtimeTranscriber(provider: provider, settings: store.transcriptionSettings, apiKey: apiKey)
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
