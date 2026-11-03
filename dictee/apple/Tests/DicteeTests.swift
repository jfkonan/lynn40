import XCTest
@testable import Dictee

final class MultipartFormDataTests: XCTestCase {
    func testBodyContainsFieldsFileAndClosingBoundary() {
        var form = MultipartFormData(boundary: "XYZ")
        form.addField(name: "model", value: "gpt-4o-transcribe")
        form.addFile(name: "file", filename: "a.wav", mimeType: "audio/wav", data: Data("AUDIO".utf8))
        let body = String(decoding: form.finalized(), as: UTF8.self)

        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=XYZ")
        XCTAssertTrue(body.contains("--XYZ\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\nAUDIO\r\n"))
        XCTAssertTrue(body.hasSuffix("--XYZ--\r\n"))
    }

    func testFieldWithContentType() {
        var form = MultipartFormData(boundary: "XYZ")
        form.addField(name: "definition", value: "{}", contentType: "application/json")
        let body = String(decoding: form.finalized(), as: UTF8.self)
        XCTAssertEqual(body, "--XYZ\r\nContent-Disposition: form-data; name=\"definition\"\r\nContent-Type: application/json\r\n\r\n{}\r\n--XYZ--\r\n")
    }
}

final class OpenAIClientTests: XCTestCase {
    private let base = URL(string: "https://api.openai.com/v1")!

    func testTranscriptionRequestHasHeadersAndFields() throws {
        let (request, body) = try OpenAIClient.makeTranscriptionRequest(
            baseURL: base, apiKey: "sk-test", audio: Data([0, 1]), filename: "x.wav",
            model: "gpt-4o-transcribe", language: "fr", prompt: "OHADA, AUSCGIE"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(text.contains("name=\"language\"\r\n\r\nfr\r\n"))
        XCTAssertTrue(text.contains("name=\"prompt\"\r\n\r\nOHADA, AUSCGIE\r\n"))
        XCTAssertTrue(text.contains("Content-Type: audio/wav"))
    }

    func testEmptyLanguageAndPromptAreOmitted() throws {
        let (_, body) = try OpenAIClient.makeTranscriptionRequest(
            baseURL: base, apiKey: "sk-test", audio: Data(), filename: "x.wav",
            model: "whisper-1", language: "  ", prompt: ""
        )
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(text.contains("name=\"language\""))
        XCTAssertFalse(text.contains("name=\"prompt\""))
    }

    func testMissingKeyThrows() {
        XCTAssertThrowsError(try OpenAIClient.makeTranscriptionRequest(
            baseURL: base, apiKey: "", audio: Data(), filename: "x.wav", model: "m", language: nil, prompt: nil
        )) { error in
            XCTAssertEqual(error as? OpenAIClient.ClientError, .missingAPIKey)
        }
    }

    func testParsers() throws {
        XCTAssertEqual(try OpenAIClient.parseTranscription(Data(#"{"text":"Bonjour"}"#.utf8)), "Bonjour")
        XCTAssertEqual(
            try OpenAIClient.parseChat(Data(#"{"choices":[{"message":{"content":" Texte. "}}]}"#.utf8)),
            "Texte."
        )
        XCTAssertEqual(
            OpenAIClient.errorMessage(from: Data(#"{"error":{"message":"Invalid API key"}}"#.utf8)),
            "Invalid API key"
        )
        XCTAssertThrowsError(try OpenAIClient.parseTranscription(Data("oops".utf8)))
    }

    func testCleanupRequestOmitsTemperatureForReasoningModels() throws {
        func payload(_ model: String) throws -> [String: Any] {
            let request = try OpenAIClient.makeCleanupRequest(baseURL: base, apiKey: "k", text: "t", model: model, vocabulary: "OHADA")
            return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        }
        XCTAssertNotNil(try payload("gpt-4o-mini")["temperature"])
        XCTAssertNil(try payload("o4-mini")["temperature"])
        XCTAssertTrue(OpenAIClient.cleanupInstructions(vocabulary: "OHADA").contains("OHADA"))
    }
}

final class SharedStoreTests: XCTestCase {
    private var suiteName = ""
    private var store: SharedStore!

    override func setUp() {
        suiteName = "dictee-tests-\(UUID().uuidString)"
        store = SharedStore(defaults: UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func testDefaults() {
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.model, SharedStore.Default.model)
        XCTAssertEqual(store.sessionMinutes, SharedStore.Default.sessionMinutes)
        XCTAssertFalse(store.isSessionAlive())
    }

    func testSessionAliveUsesExpiry() {
        let now = Date()
        store.sessionExpiresAt = now.addingTimeInterval(5)
        XCTAssertTrue(store.isSessionAlive(now: now))
        XCTAssertFalse(store.isSessionAlive(now: now.addingTimeInterval(6)))
    }

    func testTranscriptIsInsertedOnlyOnceAndOnlyWhenRecent() {
        let now = Date()
        let transcript = Transcript(id: "1", text: "Bonjour", createdAt: now)
        store.latestTranscript = transcript

        XCTAssertEqual(store.unconsumedTranscript(now: now), transcript)
        XCTAssertNil(store.unconsumedTranscript(maxAge: 120, now: now.addingTimeInterval(121)))

        store.markConsumed(transcript)
        XCTAssertNil(store.unconsumedTranscript(now: now))
    }

    func testEmptyModelFallsBackToDefault() {
        store.defaults.set("  ", forKey: SharedStore.Key.model)
        XCTAssertEqual(store.model, SharedStore.Default.model)
    }

    // MARK: - Fournisseurs (SPEC §3)

    func testProviderSettingsDefaultsMatchSpec() {
        XCTAssertEqual(store.provider, .openai)
        XCTAssertEqual(store.model, "gpt-transcribe")
        XCTAssertEqual(store.mistralModel, "voxtral-small-transcribe-3")
        XCTAssertEqual(store.microsoftModel, "mai-transcribe-2")
        XCTAssertEqual(store.azureRegion, "eastus")
        XCTAssertEqual(SharedStore.Key.provider, "dictee.settings.provider")
        XCTAssertEqual(SharedStore.Key.mistralModel, "dictee.settings.mistralModel")
        XCTAssertEqual(SharedStore.Key.microsoftModel, "dictee.settings.microsoftModel")
        XCTAssertEqual(SharedStore.Key.azureRegion, "dictee.settings.azureRegion")
    }

    func testProviderIsReadAndUnknownValueFallsBackToOpenAI() {
        store.defaults.set("mistral", forKey: SharedStore.Key.provider)
        XCTAssertEqual(store.provider, .mistral)
        store.defaults.set("microsoft", forKey: SharedStore.Key.provider)
        XCTAssertEqual(store.provider, .microsoft)
        store.defaults.set("anthropic", forKey: SharedStore.Key.provider)
        XCTAssertEqual(store.provider, .openai)
        store.defaults.set("", forKey: SharedStore.Key.provider)
        XCTAssertEqual(store.provider, .openai)
    }

    func testBlankProviderModelsAndRegionFallBackToDefaults() {
        store.defaults.set("", forKey: SharedStore.Key.mistralModel)
        store.defaults.set("  ", forKey: SharedStore.Key.microsoftModel)
        store.defaults.set(" \n", forKey: SharedStore.Key.azureRegion)
        XCTAssertEqual(store.mistralModel, "voxtral-small-transcribe-3")
        XCTAssertEqual(store.microsoftModel, "mai-transcribe-2")
        XCTAssertEqual(store.azureRegion, "eastus")

        store.defaults.set(" voxtral-mini-transcribe-3 ", forKey: SharedStore.Key.mistralModel)
        store.defaults.set("westeurope", forKey: SharedStore.Key.azureRegion)
        XCTAssertEqual(store.mistralModel, "voxtral-mini-transcribe-3")
        XCTAssertEqual(store.azureRegion, "westeurope")
    }

    func testTranscriptionSettingsMirrorStore() {
        store.defaults.set("whisper-1", forKey: SharedStore.Key.model)
        store.defaults.set("swedencentral", forKey: SharedStore.Key.azureRegion)
        store.defaults.set("en", forKey: SharedStore.Key.language)
        let settings = store.transcriptionSettings
        XCTAssertEqual(settings.openAIModel, "whisper-1")
        XCTAssertEqual(settings.mistralModel, SharedStore.Default.mistralModel)
        XCTAssertEqual(settings.microsoftModel, SharedStore.Default.microsoftModel)
        XCTAssertEqual(settings.azureRegion, "swedencentral")
        XCTAssertEqual(settings.language, "en")
        XCTAssertEqual(settings.vocabulary, SharedStore.Default.vocabulary)
    }
}

final class TextJoinerTests: XCTestCase {
    func testSpacing() {
        XCTAssertEqual(TextJoiner.textToInsert("Bonjour", before: nil), "Bonjour")
        XCTAssertEqual(TextJoiner.textToInsert("Bonjour", before: ""), "Bonjour")
        XCTAssertEqual(TextJoiner.textToInsert("le monde", before: "Bonjour"), " le monde")
        XCTAssertEqual(TextJoiner.textToInsert("le monde", before: "Bonjour "), "le monde")
        XCTAssertEqual(TextJoiner.textToInsert("texte", before: "«"), "texte")
        XCTAssertEqual(TextJoiner.textToInsert("  \n", before: "a"), "")
    }
}

// MARK: - Fournisseurs de transcription (SPEC §2 bis)

/// Nombre d'occurrences de `needle` dans `text`.
private func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

final class TranscriptionProviderTests: XCTestCase {
    func testRawValuesAndDisplayNames() {
        XCTAssertEqual(TranscriptionProvider.allCases.map(\.rawValue), ["openai", "mistral", "microsoft"])
        XCTAssertEqual(TranscriptionProvider.allCases.map(\.displayName), ["OpenAI", "Mistral", "Microsoft"])
    }

    func testStoredValueFallsBackToOpenAI() {
        XCTAssertEqual(TranscriptionProvider(storedValue: "mistral"), .mistral)
        XCTAssertEqual(TranscriptionProvider(storedValue: "microsoft"), .microsoft)
        XCTAssertEqual(TranscriptionProvider(storedValue: "inconnu"), .openai)
        XCTAssertEqual(TranscriptionProvider(storedValue: ""), .openai)
        XCTAssertEqual(TranscriptionProvider(storedValue: nil), .openai)
    }

    func testKeychainAccountsMatchSpec() {
        XCTAssertEqual(TranscriptionProvider.openai.keychainAccount, "apiKey")
        XCTAssertEqual(TranscriptionProvider.mistral.keychainAccount, "apiKey.mistral")
        XCTAssertEqual(TranscriptionProvider.microsoft.keychainAccount, "apiKey.microsoft")
    }

    func testDefaultModelsAndChoices() {
        XCTAssertEqual(TranscriptionProvider.openai.defaultModel, "gpt-transcribe")
        XCTAssertEqual(TranscriptionProvider.mistral.defaultModel, "voxtral-small-transcribe-3")
        XCTAssertEqual(TranscriptionProvider.microsoft.defaultModel, "mai-transcribe-2")
        XCTAssertEqual(
            TranscriptionProvider.openai.suggestedModels,
            ["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]
        )
        XCTAssertEqual(TranscriptionProvider.mistral.suggestedModels, ["voxtral-small-transcribe-3", "voxtral-mini-transcribe-3"])
        // Saisie libre : ajoutée à la liste ; valeur connue ou vide : liste inchangée.
        XCTAssertEqual(
            TranscriptionProvider.mistral.modelChoices(including: "voxtral-custom"),
            ["voxtral-small-transcribe-3", "voxtral-mini-transcribe-3", "voxtral-custom"]
        )
        XCTAssertEqual(TranscriptionProvider.openai.modelChoices(including: "whisper-1"), TranscriptionProvider.openai.suggestedModels)
        XCTAssertEqual(TranscriptionProvider.openai.modelChoices(including: " "), TranscriptionProvider.openai.suggestedModels)
    }

    func testNotes() {
        XCTAssertEqual(TranscriptionProvider.mistral.note, "Mistral : hébergé dans l'UE.")
        XCTAssertEqual(TranscriptionProvider.microsoft.note, "Microsoft : preview, prix promotionnel jusqu'au 31/12/2026.")
    }

    func testKeysToShowIncludeOpenAIWhenCleanupIsOn() {
        XCTAssertEqual(TranscriptionProvider.providersNeedingKeys(selected: .openai, cleanupEnabled: true), [.openai])
        XCTAssertEqual(TranscriptionProvider.providersNeedingKeys(selected: .mistral, cleanupEnabled: false), [.mistral])
        XCTAssertEqual(TranscriptionProvider.providersNeedingKeys(selected: .mistral, cleanupEnabled: true), [.mistral, .openai])
        XCTAssertEqual(TranscriptionProvider.providersNeedingKeys(selected: .microsoft, cleanupEnabled: true), [.microsoft, .openai])
    }

    func testProviderKeysAreTrimmedAndEmptyMeansMissing() {
        let keys = ProviderKeys(openAI: " sk-openai ", mistral: "  ", microsoft: nil)
        XCTAssertEqual(keys.key(for: .openai), "sk-openai")
        XCTAssertNil(keys.key(for: .mistral))
        XCTAssertNil(keys.key(for: .microsoft))
    }
}

final class VocabularyTermsTests: XCTestCase {
    func testSplitsOnCommasSemicolonsAndNewlines() {
        XCTAssertEqual(
            TranscriptionService.vocabularyTerms(" OHADA, AUSCGIE ;CCJA\nSARL\r\nassemblée générale ,, ;\n"),
            ["OHADA", "AUSCGIE", "CCJA", "SARL", "assemblée générale"]
        )
    }

    func testDuplicatesAreRemovedKeepingTheFirst() {
        XCTAssertEqual(TranscriptionService.vocabularyTerms("SA, SAS, SA, SARL; SAS"), ["SA", "SAS", "SARL"])
    }

    func testAtMost100Terms() {
        let vocabulary = (1...150).map { "terme\($0)" }.joined(separator: ", ")
        let terms = TranscriptionService.vocabularyTerms(vocabulary)
        XCTAssertEqual(terms.count, 100)
        XCTAssertEqual(terms.first, "terme1")
        XCTAssertEqual(terms.last, "terme100")
    }

    func testEmptyVocabularyGivesNoTerm() {
        XCTAssertEqual(TranscriptionService.vocabularyTerms(""), [])
        XCTAssertEqual(TranscriptionService.vocabularyTerms(" , ;\n "), [])
    }

    func testDefaultVocabularyHas18Terms() {
        XCTAssertEqual(TranscriptionService.vocabularyTerms(SharedStore.Default.vocabulary).count, 18)
    }
}

final class LanguageCodeTests: XCTestCase {
    func testAzureLocale() {
        XCTAssertEqual(TranscriptionService.azureLocale(for: "fr"), "fr-FR")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "en"), "en-US")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "es"), "es-ES")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "de"), "de-DE")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "it"), "it-IT")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "pt"), "pt-BR")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "nl"), "nl-NL")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "ar"), "ar-SA")
        XCTAssertEqual(TranscriptionService.azureLocale(for: " FR "), "fr-FR")
    }

    func testAzureLocaleKeepsComposedValueAndBuildsOtherTwoLetterCodes() {
        XCTAssertEqual(TranscriptionService.azureLocale(for: "fr-CA"), "fr-CA")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "en-GB"), "en-GB")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "xx"), "xx-XX")
        XCTAssertEqual(TranscriptionService.azureLocale(for: "sw"), "sw-SW")
    }

    func testAzureLocaleIsNilForEmptyLanguage() {
        XCTAssertNil(TranscriptionService.azureLocale(for: ""))
        XCTAssertNil(TranscriptionService.azureLocale(for: "   "))
    }

    func testMistralLanguageIsTwoLetters() {
        XCTAssertEqual(TranscriptionService.mistralLanguage(for: "fr"), "fr")
        XCTAssertEqual(TranscriptionService.mistralLanguage(for: "fr-FR"), "fr")
        XCTAssertEqual(TranscriptionService.mistralLanguage(for: " EN_us "), "en")
        XCTAssertNil(TranscriptionService.mistralLanguage(for: ""))
        XCTAssertNil(TranscriptionService.mistralLanguage(for: nil))
    }
}

final class MistralRequestTests: XCTestCase {
    func testRequestMatchesSpec() throws {
        let (request, body) = try TranscriptionService.makeMistralRequest(
            apiKey: "mistral-key", audio: Data([0, 1]), filename: "dictee-1.wav",
            model: "voxtral-small-transcribe-3", language: "fr-FR", vocabulary: "OHADA, CCJA; SARL\nOHADA"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 120)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mistral-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\nvoxtral-small-transcribe-3\r\n"))
        XCTAssertTrue(text.contains("name=\"language\"\r\n\r\nfr\r\n"))
        XCTAssertEqual(occurrences(of: "name=\"context_bias\"", in: text), 3)
        XCTAssertTrue(text.contains("name=\"context_bias\"\r\n\r\nOHADA\r\n"))
        XCTAssertTrue(text.contains("name=\"context_bias\"\r\n\r\nCCJA\r\n"))
        XCTAssertTrue(text.contains("name=\"context_bias\"\r\n\r\nSARL\r\n"))
        XCTAssertFalse(text.contains("name=\"prompt\""))
        XCTAssertFalse(text.contains("name=\"response_format\""))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"dictee-1.wav\"\r\nContent-Type: audio/wav\r\n"))
    }

    func testEmptyLanguageAndVocabularyAreOmitted() throws {
        let (_, body) = try TranscriptionService.makeMistralRequest(
            apiKey: "k", audio: Data(), filename: "x.wav", model: "voxtral-mini-transcribe-3", language: " ", vocabulary: ""
        )
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(text.contains("name=\"language\""))
        XCTAssertFalse(text.contains("name=\"context_bias\""))
    }

    func testMissingKeyNamesMistral() {
        XCTAssertThrowsError(try TranscriptionService.makeMistralRequest(
            apiKey: " ", audio: Data(), filename: "x.wav", model: "m", language: nil, vocabulary: ""
        )) { error in
            XCTAssertEqual(error as? TranscriptionError, .missingAPIKey(.mistral))
        }
    }
}

final class AzureRequestTests: XCTestCase {
    func testRequestMatchesSpec() throws {
        let (request, body) = try TranscriptionService.makeAzureRequest(
            region: "westeurope", apiKey: "azure-key", audio: Data("AUDIO".utf8),
            model: "mai-transcribe-2", language: "fr", vocabulary: "OHADA, CCJA"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://westeurope.api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 120)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key"), "azure-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(text.contains("name=\"audio\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\nAUDIO\r\n"))
        XCTAssertTrue(text.contains("name=\"definition\"\r\nContent-Type: application/json\r\n\r\n{"))
        let definition = try TranscriptionService.azureDefinition(model: "mai-transcribe-2", language: "fr", vocabulary: "OHADA, CCJA")
        XCTAssertTrue(text.contains(String(decoding: definition, as: UTF8.self)))
        XCTAssertEqual(occurrences(of: "Content-Disposition: form-data;", in: text), 2)
    }

    func testDefinitionJSON() throws {
        let data = try TranscriptionService.azureDefinition(model: "mai-transcribe-2", language: "fr", vocabulary: "OHADA, AUSCGIE, OHADA")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["locales"] as? [String], ["fr-FR"])
        let enhanced = try XCTUnwrap(json["enhancedMode"] as? [String: Any])
        XCTAssertEqual(enhanced["enabled"] as? Bool, true)
        XCTAssertEqual(enhanced["model"] as? String, "mai-transcribe-2")
        let phraseList = try XCTUnwrap(json["phraseList"] as? [String: Any])
        XCTAssertEqual(phraseList["phrases"] as? [String], ["OHADA", "AUSCGIE"])
    }

    func testLocalesAndPhraseListOmittedWhenEmpty() throws {
        let data = try TranscriptionService.azureDefinition(model: "mai-transcribe-2", language: "", vocabulary: " ; ")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["locales"])
        XCTAssertNil(json["phraseList"])
        XCTAssertNotNil(json["enhancedMode"])
    }

    func testRegionIsNormalizedAndValidated() throws {
        XCTAssertEqual(
            try TranscriptionService.azureURL(region: " SwedenCentral ").host,
            "swedencentral.api.cognitive.microsoft.com"
        )
        for bad in ["", "west europe", "evil.com/x", "-eastus", "eastus-", "east_us"] {
            XCTAssertThrowsError(try TranscriptionService.azureURL(region: bad)) { error in
                XCTAssertEqual(error as? TranscriptionError, .invalidAzureRegion)
            }
        }
    }

    func testMissingKeyNamesMicrosoft() {
        XCTAssertThrowsError(try TranscriptionService.makeAzureRequest(
            region: "eastus", apiKey: "", audio: Data(), model: "m", language: "fr", vocabulary: ""
        )) { error in
            XCTAssertEqual(error as? TranscriptionError, .missingAPIKey(.microsoft))
        }
    }
}

final class TranscriptionResponseTests: XCTestCase {
    func testAzureReadsCombinedPhrases() throws {
        let json = #"{"combinedPhrases":[{"text":"Bonjour le monde."}],"phrases":[{"text":"Bonjour"},{"text":"le monde."}]}"#
        XCTAssertEqual(try TranscriptionService.parseAzureTranscription(Data(json.utf8)), "Bonjour le monde.")
    }

    func testAzureFallsBackToPhrases() throws {
        let json = #"{"phrases":[{"text":"Bonjour"},{"text":" "},{"text":"le monde."}]}"#
        XCTAssertEqual(try TranscriptionService.parseAzureTranscription(Data(json.utf8)), "Bonjour le monde.")
        let emptyCombined = #"{"combinedPhrases":[],"phrases":[{"text":"Salut"}]}"#
        XCTAssertEqual(try TranscriptionService.parseAzureTranscription(Data(emptyCombined.utf8)), "Salut")
    }

    func testAzureSilenceGivesEmptyText() throws {
        XCTAssertEqual(try TranscriptionService.parseAzureTranscription(Data(#"{"combinedPhrases":[]}"#.utf8)), "")
    }

    func testAzureUnreadableResponseThrows() {
        for body in ["{}", "oops"] {
            XCTAssertThrowsError(try TranscriptionService.parseAzureTranscription(Data(body.utf8))) { error in
                XCTAssertEqual(error as? TranscriptionError, .invalidResponse(.microsoft))
            }
        }
    }

    func testMistralTextResponse() throws {
        let json = #"{"model":"voxtral-small-transcribe-3","text":"Bonjour","language":"fr"}"#
        XCTAssertEqual(try TranscriptionService.parseTextResponse(Data(json.utf8), provider: .mistral), "Bonjour")
        XCTAssertThrowsError(try TranscriptionService.parseTextResponse(Data("{}".utf8), provider: .mistral)) { error in
            XCTAssertEqual(error as? TranscriptionError, .invalidResponse(.mistral))
        }
    }

    func testErrorMessageForms() {
        func message(_ body: String) -> String { TranscriptionService.errorMessage(from: Data(body.utf8)) }
        XCTAssertEqual(message(#"{"error":{"code":"401","message":"Access denied"}}"#), "Access denied")
        XCTAssertEqual(message(#"{"object":"error","message":"Unauthorized","type":"auth"}"#), "Unauthorized")
        XCTAssertEqual(message(#"{"detail":"Model not found"}"#), "Model not found")
        XCTAssertEqual(message(#"{"detail":[{"msg":"Field required"}]}"#), #"[{"msg":"Field required"}]"#)
        // error.message prime sur message, qui prime sur detail.
        XCTAssertEqual(message(#"{"error":{"message":"A"},"message":"B","detail":"C"}"#), "A")
        XCTAssertEqual(message(#"{"message":"B","detail":"C"}"#), "B")
        // Ni l'un ni l'autre : 300 premiers caractères du corps.
        let html = "<html>" + String(repeating: "x", count: 400)
        XCTAssertEqual(message(html), String(html.prefix(300)))
        XCTAssertEqual(message(#"{"foo":1}"#), #"{"foo":1}"#)
    }

    func testErrorMessageHidesKeys() {
        XCTAssertEqual(
            TranscriptionService.errorMessage(from: Data(#"{"error":{"message":"Incorrect API key provided: sk-proj-ab12****wxyz."}}"#.utf8)),
            "Incorrect API key provided: sk-…wxyz."
        )
        XCTAssertEqual(
            TranscriptionService.redactKeys("Clé refusée : abcdefghijkl", apiKey: "abcdefghijkl"),
            "Clé refusée : abc…ijkl"
        )
    }

    func testErrorDescriptionsNameTheProvider() {
        XCTAssertEqual(
            TranscriptionError.missingAPIKey(.mistral).errorDescription,
            "Clé API Mistral manquante. Ajoutez-la dans les réglages de Dictée."
        )
        XCTAssertEqual(
            TranscriptionError.missingAPIKey(.microsoft).errorDescription,
            "Clé API Microsoft manquante. Ajoutez-la dans les réglages de Dictée."
        )
        XCTAssertEqual(
            TranscriptionError.missingAPIKey(.openai).errorDescription,
            OpenAIClient.ClientError.missingAPIKey.errorDescription
        )
        XCTAssertEqual(
            TranscriptionError.http(provider: .mistral, status: 401, message: "Unauthorized").errorDescription,
            "Erreur Mistral (401) : Unauthorized"
        )
        XCTAssertEqual(
            TranscriptionError.http(provider: .microsoft, status: 400, message: "Invalid locale").errorDescription,
            "Erreur Microsoft (400) : Invalid locale"
        )
    }

    func testCleanupIsSkippedWithoutOpenAIKey() {
        XCTAssertFalse(TranscriptionRules.shouldCleanUp(enabled: true, raw: "euh bonjour", openAIKey: nil))
        XCTAssertFalse(TranscriptionRules.shouldCleanUp(enabled: true, raw: "euh bonjour", openAIKey: "  "))
        XCTAssertFalse(TranscriptionRules.shouldCleanUp(enabled: false, raw: "euh bonjour", openAIKey: "sk-test"))
        XCTAssertTrue(TranscriptionRules.shouldCleanUp(enabled: true, raw: "euh bonjour", openAIKey: "sk-test"))
    }

    func testServiceChecksTheProviderKeyBeforeAnyNetworkCall() async {
        // Clé OpenAI présente, mais pas celle de Mistral : erreur nommant Mistral, sans lire le fichier.
        do {
            _ = try await TranscriptionService.transcribe(
                provider: .mistral,
                audioURL: URL(fileURLWithPath: "/dossier/inexistant.wav"),
                settings: TranscriptionSettings(),
                keys: ProviderKeys(openAI: "sk-test")
            )
            XCTFail("Une clé Mistral manquante doit lever une erreur.")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .missingAPIKey(.mistral))
        }
    }

    func testCleanupHelperReturnsNilWithoutOpenAIKey() async {
        let cleaned = await TranscriptionService.cleanUp(
            raw: "euh bonjour", enabled: true, model: "gpt-4o-mini", vocabulary: "", openAIKey: nil
        )
        XCTAssertNil(cleaned)
    }
}
