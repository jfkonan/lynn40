import Foundation

/// Protocole de transcription en continu (SPEC §2 ter), fonctions pures : URL, en-têtes, messages JSON et lecture des
/// événements, pour OpenAI (`gpt-live-transcribe`) et Mistral (Voxtral Realtime). Microsoft : à faire (SPEC §2 ter).
enum RealtimeProtocol {
    /// Ce que le serveur nous dit, ramené à l'essentiel.
    enum Event: Equatable {
        /// `session.updated` : les réglages sont acceptés, l'audio peut partir.
        case ready
        /// Fragment de texte définitif, à concaténer tel quel.
        case delta(String)
        /// Texte final complet (fait foi sur les deltas).
        case completed(String)
        case error(String)
        /// Événement sans intérêt pour nous (`session.created`, `input_audio_buffer.committed`…).
        case ignored
    }

    /// Réactivité demandée à `gpt-live-transcribe` (`minimal`, `low`, `medium`, `high`, `xhigh`) : plus bas = texte plus tôt,
    /// moins de contexte. Mesuré en recette (SPEC §2 ter) ; `low` garde une marge de précision sur `minimal`.
    static let openAIDelay = "low"

    /// Le fournisseur a-t-il un protocole implémenté ?
    static func supports(_ provider: TranscriptionProvider) -> Bool {
        switch provider {
        case .openai, .mistral: return true
        case .microsoft: return false
        }
    }

    /// Fréquence d'échantillonnage attendue (PCM16 mono).
    static func sampleRate(for provider: TranscriptionProvider) -> Double {
        switch provider {
        case .openai: return 24_000
        case .mistral, .microsoft: return 16_000
        }
    }

    static func url(for provider: TranscriptionProvider, settings: TranscriptionSettings) -> URL? {
        switch provider {
        case .openai:
            return URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")
        case .mistral:
            var components = URLComponents(string: "wss://api.mistral.ai/v1/audio/transcriptions/realtime")
            components?.queryItems = [URLQueryItem(name: "model", value: settings.mistralRealtimeModel)]
            return components?.url
        case .microsoft:
            return nil
        }
    }

    static func headers(for provider: TranscriptionProvider, apiKey: String) -> [String: String] {
        switch provider {
        case .openai, .mistral: return ["Authorization": "Bearer \(apiKey)"]
        case .microsoft: return ["api-key": apiKey]
        }
    }

    /// Message de configuration de la session, à envoyer après `session.created`.
    static func sessionUpdate(for provider: TranscriptionProvider, settings: TranscriptionSettings) -> Data {
        // Code à 2 lettres (« fr-FR » → « fr »), comme pour Mistral en fichier (SPEC §2 bis) ; vide = détection.
        let language = TranscriptionService.mistralLanguage(for: settings.language) ?? ""
        let terms = TranscriptionService.vocabularyTerms(settings.vocabulary)
        var session: [String: Any]
        switch provider {
        case .openai:
            var transcription: [String: Any] = ["model": settings.openAIRealtimeModel, "delay": openAIDelay]
            if !language.isEmpty { transcription["languages"] = [language] }
            let keywords = terms.filter { !$0.contains("<") && !$0.contains(">") && !$0.contains("\n") && !$0.contains("\r") }
            if !keywords.isEmpty { transcription["keywords"] = keywords }
            session = [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": Int(sampleRate(for: .openai))],
                        "transcription": transcription,
                        "turn_detection": NSNull(),
                    ],
                ],
            ]
        case .mistral, .microsoft:
            session = [
                "audio_format": ["encoding": "pcm_s16le", "sample_rate": Int(sampleRate(for: .mistral))],
                "target_streaming_delay_ms": 480,
            ]
            if !language.isEmpty { session["language"] = language }
            if !terms.isEmpty { session["context_bias"] = terms }
        }
        return json(["type": "session.update", "session": session])
    }

    /// Un morceau d'audio PCM16 (sans en-tête).
    static func append(for provider: TranscriptionProvider, pcm: Data) -> Data {
        let type = provider == .openai ? "input_audio_buffer.append" : "input_audio.append"
        return json(["type": type, "audio": pcm.base64EncodedString()])
    }

    /// Fin de l'audio : demande le texte final.
    static func end(for provider: TranscriptionProvider) -> Data {
        json(["type": provider == .openai ? "input_audio_buffer.commit" : "input_audio.end"])
    }

    static func parse(_ data: Data, provider: TranscriptionProvider) -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return .ignored }
        switch type {
        case "session.updated":
            return .ready
        case "error", "conversation.item.input_audio_transcription.failed":
            return .error(errorMessage(in: object))
        case "conversation.item.input_audio_transcription.delta":
            return .delta(object["delta"] as? String ?? "")
        case "conversation.item.input_audio_transcription.completed":
            return .completed(object["transcript"] as? String ?? "")
        case "transcription.text.delta":
            return .delta(object["text"] as? String ?? "")
        case "transcription.done":
            return .completed(object["text"] as? String ?? "")
        default:
            return .ignored
        }
    }

    /// Texte final : le texte complet s'il est non vide, sinon les deltas assemblés tels quels.
    static func finalText(completed: String?, deltas: [String]) -> String {
        let full = completed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !full.isEmpty { return full }
        return deltas.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func errorMessage(in object: [String: Any]) -> String {
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? String { return error }
        return "Erreur de transcription en continu."
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
