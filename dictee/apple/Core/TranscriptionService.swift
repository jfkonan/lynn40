import Foundation

/// Réglages utiles à la transcription (SPEC §3), lus d'un coup dans SharedStore avant l'appel réseau.
struct TranscriptionSettings: Equatable, Sendable {
    var openAIModel: String
    var mistralModel: String
    var microsoftModel: String
    var azureRegion: String
    var language: String
    var vocabulary: String

    init(
        openAIModel: String = SharedStore.Default.model,
        mistralModel: String = SharedStore.Default.mistralModel,
        microsoftModel: String = SharedStore.Default.microsoftModel,
        azureRegion: String = SharedStore.Default.azureRegion,
        language: String = SharedStore.Default.language,
        vocabulary: String = SharedStore.Default.vocabulary
    ) {
        self.openAIModel = openAIModel
        self.mistralModel = mistralModel
        self.microsoftModel = microsoftModel
        self.azureRegion = azureRegion
        self.language = language
        self.vocabulary = vocabulary
    }
}

/// Clés API des trois fournisseurs (SPEC §4), lues dans le Trousseau par `KeychainStore.loadAllKeys()`.
struct ProviderKeys: Equatable, Sendable {
    var openAI: String?
    var mistral: String?
    var microsoft: String?

    init(openAI: String? = nil, mistral: String? = nil, microsoft: String? = nil) {
        self.openAI = openAI
        self.mistral = mistral
        self.microsoft = microsoft
    }

    /// Clé du fournisseur, sans espaces de bord ; `nil` si elle est absente ou vide.
    func key(for provider: TranscriptionProvider) -> String? {
        let raw: String?
        switch provider {
        case .openai: raw = openAI
        case .mistral: raw = mistral
        case .microsoft: raw = microsoft
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Erreurs de transcription, avec le nom du fournisseur dans le message (SPEC §2.6 et §4).
enum TranscriptionError: LocalizedError, Equatable {
    case missingAPIKey(TranscriptionProvider)
    case http(provider: TranscriptionProvider, status: Int, message: String)
    case invalidResponse(TranscriptionProvider)
    case invalidAzureRegion

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            return "Clé API \(provider.displayName) manquante. Ajoutez-la dans les réglages de Dictée."
        case let .http(provider, status, message):
            return "Erreur \(provider.displayName) (\(status)) : \(message)"
        case let .invalidResponse(provider):
            return "Réponse \(provider.displayName) illisible."
        case .invalidAzureRegion:
            return "Région Azure invalide. Indiquez dans les réglages le nom de la région de votre ressource (ex. westeurope, swedencentral)."
        }
    }
}

/// Point d'entrée unique de la transcription (SPEC §2 et §2 bis), utilisé par l'app iOS et l'app Mac.
/// Les constructeurs de requêtes et les parseurs sont des fonctions pures, testées sans réseau.
enum TranscriptionService {
    static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!
    static let mistralBaseURL = URL(string: "https://api.mistral.ai/v1")!
    static let azureAPIVersion = "2025-10-15"
    static let maxVocabularyTerms = 100
    static let transcriptionTimeout: TimeInterval = 120
    /// Au-delà, le corps d'une réponse d'erreur illisible est tronqué (SPEC §2.6).
    static let maxErrorLength = 300

    // MARK: - Transcription

    /// Transcrit le fichier audio avec le fournisseur choisi. La clé du fournisseur est vérifiée avant tout accès réseau.
    /// Le fichier n'est pas supprimé ici : c'est à l'appelant de le faire, dans tous les cas (SPEC §2.5).
    static func transcribe(
        provider: TranscriptionProvider,
        audioURL: URL,
        settings: TranscriptionSettings,
        keys: ProviderKeys,
        session: URLSession = .shared
    ) async throws -> String {
        guard let apiKey = keys.key(for: provider) else {
            throw TranscriptionError.missingAPIKey(provider)
        }

        switch provider {
        case .openai:
            let client = OpenAIClient(apiKey: apiKey, session: session)
            do {
                return try await client.transcribe(
                    audioURL: audioURL,
                    model: settings.openAIModel,
                    language: settings.language,
                    prompt: settings.vocabulary
                )
            } catch OpenAIClient.ClientError.http(let status, let message) {
                throw OpenAIClient.ClientError.http(status: status, message: redactKeys(message, apiKey: apiKey))
            }

        case .mistral:
            let audio = try Data(contentsOf: audioURL)
            let (request, body) = try makeMistralRequest(
                apiKey: apiKey,
                audio: audio,
                filename: audioURL.lastPathComponent,
                model: settings.mistralModel,
                language: settings.language,
                vocabulary: settings.vocabulary
            )
            let (data, response) = try await session.upload(for: request, from: body)
            try validate(response: response, data: data, provider: .mistral, apiKey: apiKey)
            return try parseTextResponse(data, provider: .mistral)

        case .microsoft:
            let audio = try Data(contentsOf: audioURL)
            let (request, body) = try makeAzureRequest(
                region: settings.azureRegion,
                apiKey: apiKey,
                audio: audio,
                model: settings.microsoftModel,
                language: settings.language,
                vocabulary: settings.vocabulary
            )
            let (data, response) = try await session.upload(for: request, from: body)
            try validate(response: response, data: data, provider: .microsoft, apiKey: apiKey)
            return try parseAzureTranscription(data)
        }
    }

    /// Nettoyage optionnel (SPEC §2.3), toujours chez OpenAI avec la clé OpenAI, quel que soit le fournisseur.
    /// Il s'exécute si `enabled` est vrai **ou** si le style d'écriture n'est pas `brut` (SPEC §2, « Style d'écriture »).
    /// Renvoie `nil` s'il n'est pas demandé, inutile (texte vide), sans clé OpenAI, ou en échec :
    /// `TranscriptionRules.finalText` garde alors le texte brut.
    static func cleanUp(
        raw: String,
        enabled: Bool,
        style: WritingStyle = .brut,
        model: String,
        vocabulary: String,
        openAIKey: String?,
        session: URLSession = .shared
    ) async -> String? {
        guard TranscriptionRules.shouldCleanUp(enabled: enabled, style: style, raw: raw, openAIKey: openAIKey),
              let key = ProviderKeys(openAI: openAIKey).key(for: .openai) else { return nil }
        let client = OpenAIClient(apiKey: key, session: session)
        return try? await client.cleanUp(text: raw, model: model, vocabulary: vocabulary, style: style)
    }

    // MARK: - Vocabulaire et langue

    /// Termes du vocabulaire (SPEC §2 bis) : séparés par virgules, points-virgules ou retours à la ligne,
    /// espaces de bord retirées, termes vides ignorés, doublons retirés (le premier est gardé), 100 au maximum.
    static func vocabularyTerms(_ vocabulary: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for part in vocabulary.components(separatedBy: CharacterSet(charactersIn: ",;\n\r")) {
            let term = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !seen.contains(term) else { continue }
            seen.insert(term)
            terms.append(term)
            if terms.count == maxVocabularyTerms { break }
        }
        return terms
    }

    /// Code de langue pour Mistral : 2 lettres (« fr-FR » → « fr ») ; vide → `nil` (champ omis).
    static func mistralLanguage(for language: String?) -> String? {
        var value = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let cut = value.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            value = String(value[..<cut])
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }

    private static let knownAzureLocales: [String: String] = [
        "fr": "fr-FR",
        "en": "en-US",
        "es": "es-ES",
        "de": "de-DE",
        "it": "it-IT",
        "pt": "pt-BR",
        "nl": "nl-NL",
        "ar": "ar-SA",
    ]

    /// Locale Azure déduite du réglage `language` (SPEC §2 bis) : « fr » → « fr-FR » (table du cahier des charges),
    /// valeur contenant déjà « - » reprise telle quelle, autre code à 2 lettres « xx » → « xx-XX », vide → `nil`.
    /// Une valeur d'une autre forme est transmise telle quelle : Azure signalera l'erreur.
    static func azureLocale(for language: String) -> String? {
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.contains("-") { return value }
        let lower = value.lowercased()
        if let known = knownAzureLocales[lower] { return known }
        let asciiLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        if lower.count == 2, lower.unicodeScalars.allSatisfy({ asciiLetters.contains($0) }) {
            return "\(lower)-\(lower.uppercased())"
        }
        return value
    }

    // MARK: - Mistral

    /// `POST https://api.mistral.ai/v1/audio/transcriptions` : champs `model`, `language` (2 lettres, omis si vide),
    /// un `context_bias` par terme du vocabulaire, puis `file`. Ni `prompt` ni `response_format`.
    static func makeMistralRequest(
        baseURL: URL = TranscriptionService.mistralBaseURL,
        apiKey: String,
        audio: Data,
        filename: String,
        model: String,
        language: String?,
        vocabulary: String
    ) throws -> (URLRequest, Data) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey(.mistral) }

        var form = MultipartFormData()
        form.addField(name: "model", value: model)
        if let code = mistralLanguage(for: language) {
            form.addField(name: "language", value: code)
        }
        for term in vocabularyTerms(vocabulary) {
            form.addField(name: "context_bias", value: term)
        }
        form.addFile(name: "file", filename: filename, mimeType: OpenAIClient.mimeType(for: filename), data: audio)

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        return (request, form.finalized())
    }

    // MARK: - Microsoft (Azure AI Speech, MAI-Transcribe-2)

    /// `https://<région>.api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15`.
    /// La région n'accepte que lettres, chiffres et tirets : la clé ne peut pas partir vers un autre hôte.
    static func azureURL(region: String) throws -> URL {
        let value = region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !value.isEmpty,
              !value.hasPrefix("-"),
              !value.hasSuffix("-"),
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              let url = URL(string: "https://\(value).api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version=\(azureAPIVersion)")
        else {
            throw TranscriptionError.invalidAzureRegion
        }
        return url
    }

    /// Corps multipart à deux parties : `audio` (le WAV, nom `audio.wav`) et `definition` (JSON),
    /// avec l'en-tête `Ocp-Apim-Subscription-Key`.
    static func makeAzureRequest(
        region: String,
        apiKey: String,
        audio: Data,
        model: String,
        language: String?,
        vocabulary: String
    ) throws -> (URLRequest, Data) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey(.microsoft) }
        let url = try azureURL(region: region)
        let definition = try azureDefinition(model: model, language: language, vocabulary: vocabulary)

        var form = MultipartFormData()
        form.addFile(name: "audio", filename: "audio.wav", mimeType: "audio/wav", data: audio)
        form.addField(name: "definition", value: String(decoding: definition, as: UTF8.self), contentType: "application/json")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeout
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        return (request, form.finalized())
    }

    /// `{"locales":["fr-FR"],"enhancedMode":{"enabled":true,"model":"…"},"phraseList":{"phrases":[…]}}` :
    /// `locales` omis si la langue est vide, `phraseList` omis s'il n'y a aucun terme.
    static func azureDefinition(model: String, language: String?, vocabulary: String) throws -> Data {
        let enhancedMode: [String: Any] = ["enabled": true, "model": model]
        var definition: [String: Any] = ["enhancedMode": enhancedMode]
        if let locale = azureLocale(for: language ?? "") {
            let locales: [String] = [locale]
            definition["locales"] = locales
        }
        let terms = vocabularyTerms(vocabulary)
        if !terms.isEmpty {
            let phraseList: [String: Any] = ["phrases": terms]
            definition["phraseList"] = phraseList
        }
        return try JSONSerialization.data(withJSONObject: definition, options: [.sortedKeys])
    }

    // MARK: - Réponses

    /// Réponse `{"text": "..."}` (OpenAI, Mistral).
    static func parseTextResponse(_ data: Data, provider: TranscriptionProvider) throws -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = object["text"] as? String else {
            throw TranscriptionError.invalidResponse(provider)
        }
        return text
    }

    /// Réponse Azure : `combinedPhrases[0].text` ; à défaut, les `phrases[].text` joints par des espaces.
    /// Audio sans parole : `combinedPhrases` vide, texte vide (l'appelant affichera « Aucune parole détectée. »).
    static func parseAzureTranscription(_ data: Data) throws -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw TranscriptionError.invalidResponse(.microsoft)
        }
        let combined = object["combinedPhrases"] as? [[String: Any]]
        if let text = combined?.first?["text"] as? String {
            return text
        }
        if let phrases = object["phrases"] as? [[String: Any]] {
            return phrases
                .compactMap { ($0["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        if combined != nil { return "" }
        throw TranscriptionError.invalidResponse(.microsoft)
    }

    // MARK: - Erreurs HTTP

    static func validate(response: URLResponse, data: Data, provider: TranscriptionProvider, apiKey: String?) throws {
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.invalidResponse(provider) }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscriptionError.http(
                provider: provider,
                status: http.statusCode,
                message: redactKeys(errorMessage(from: data), apiKey: apiKey)
            )
        }
    }

    /// Message d'erreur du fournisseur (SPEC §2.6) : `error.message`, sinon `message` à la racine, sinon `detail`
    /// (texte, ou JSON recopié) ; à défaut, les 300 premiers caractères du corps.
    static func errorMessage(from data: Data) -> String {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let text = nonEmptyText(error["message"]) {
                return redactKeys(text)
            }
            if let text = nonEmptyText(object["message"]) {
                return redactKeys(text)
            }
            if let text = nonEmptyText(object["detail"]) {
                return redactKeys(text)
            }
        }
        // 300 caractères (pas octets) : une coupure au milieu d'un caractère UTF-8 ne doit pas tout perdre.
        return redactKeys(String(String(decoding: data, as: UTF8.self).prefix(maxErrorLength)))
    }

    /// Texte d'une chaîne non vide ; JSON compact (tronqué) d'un objet ou d'un tableau ; `nil` sinon.
    private static func nonEmptyText(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        if value is [Any] || value is [String: Any],
           JSONSerialization.isValidJSONObject(value),
           let json = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            return String(String(decoding: json, as: UTF8.self).prefix(maxErrorLength))
        }
        return nil
    }

    /// Une clé ne doit jamais figurer dans un message d'erreur (SPEC §4) : la clé utilisée et toute chaîne `sk-…`
    /// (qu'OpenAI recopie partiellement masquée) sont remplacées par un aperçu.
    static func redactKeys(_ text: String, apiKey: String? = nil) -> String {
        var result = text
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), key.count >= 8,
           let preview = KeychainStore.preview(of: key) {
            result = result.replacingOccurrences(of: key, with: preview)
        }
        guard let regex = try? NSRegularExpression(pattern: "sk-[A-Za-z0-9_*\\-]{8,}") else { return result }
        let mutable = NSMutableString(string: result)
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() {
            let found = mutable.substring(with: match.range)
            mutable.replaceCharacters(in: match.range, with: "sk-…" + String(found.suffix(4)))
        }
        return mutable as String
    }
}

// MARK: - Réglages de transcription lus dans SharedStore

extension SharedStore {
    // `provider` (avec repli sur OpenAI) est défini dans Shared/SharedStore.swift : le clavier l'écrit aussi.

    /// Réglages de transcription, avec repli sur les valeurs par défaut pour les modèles et la région.
    var transcriptionSettings: TranscriptionSettings {
        TranscriptionSettings(
            openAIModel: model,
            mistralModel: mistralModel,
            microsoftModel: microsoftModel,
            azureRegion: azureRegion,
            language: language,
            vocabulary: vocabulary
        )
    }
}
