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
