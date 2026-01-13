import XCTest
@testable import CrateBotCore

final class HookDetectorTests: XCTestCase {

    // MARK: - HookResult Initialization Tests

    func testHookResultInitialization() {
        let result = HookDetector.HookResult(
            hook: "Drop the bass",
            confidence: 0.92,
            occurrences: 4,
            transcription: "Full lyrics transcription here",
            lyricsVerified: true
        )

        XCTAssertEqual(result.hook, "Drop the bass")
        XCTAssertEqual(result.confidence, 0.92)
        XCTAssertEqual(result.occurrences, 4)
        XCTAssertEqual(result.transcription, "Full lyrics transcription here")
        XCTAssertEqual(result.lyricsVerified, true)
    }

    func testHookResultWithDefaults() {
        let result = HookDetector.HookResult(
            hook: nil,
            confidence: 0.0,
            occurrences: 0
        )

        XCTAssertNil(result.hook)
        XCTAssertEqual(result.confidence, 0.0)
        XCTAssertEqual(result.occurrences, 0)
        XCTAssertNil(result.transcription)
        XCTAssertNil(result.lyricsVerified)
    }

    // MARK: - HookResult.hasHook Tests

    func testHasHookWithHighConfidence() {
        let result = HookDetector.HookResult(
            hook: "Feel the rhythm",
            confidence: 0.85,
            occurrences: 3
        )

        XCTAssertTrue(result.hasHook)
    }

    func testHasHookWithLowConfidence() {
        let result = HookDetector.HookResult(
            hook: "Maybe this is a hook",
            confidence: 0.4,
            occurrences: 1
        )

        XCTAssertFalse(result.hasHook)
    }

    func testHasHookAtThreshold() {
        let result = HookDetector.HookResult(
            hook: "Borderline hook",
            confidence: 0.5,
            occurrences: 2
        )

        // confidence must be > 0.5, not >= 0.5
        XCTAssertFalse(result.hasHook)
    }

    func testHasHookWithJustAboveThreshold() {
        let result = HookDetector.HookResult(
            hook: "Clear hook",
            confidence: 0.51,
            occurrences: 2
        )

        XCTAssertTrue(result.hasHook)
    }

    func testHasHookWithNilHook() {
        let result = HookDetector.HookResult(
            hook: nil,
            confidence: 0.95,
            occurrences: 0
        )

        XCTAssertFalse(result.hasHook)
    }

    // MARK: - HookError Description Tests

    func testHookErrorBackendUnavailable() {
        let error = HookDetector.HookError.backendUnavailable
        XCTAssertEqual(error.errorDescription, "Backend server is not available")
    }

    func testHookErrorDetectionFailed() {
        let error = HookDetector.HookError.detectionFailed("Processing timeout")
        XCTAssertEqual(error.errorDescription, "Hook detection failed: Processing timeout")
    }

    func testHookErrorWhisperNotAvailable() {
        let error = HookDetector.HookError.whisperNotAvailable
        XCTAssertEqual(error.errorDescription, "Whisper model is not available")
    }

    func testHookErrorNoVocalsDetected() {
        let error = HookDetector.HookError.noVocalsDetected
        XCTAssertEqual(error.errorDescription, "No vocals detected in track")
    }

    func testHookErrorInvalidFile() {
        let error = HookDetector.HookError.invalidFile("File not found")
        XCTAssertEqual(error.errorDescription, "Invalid file: File not found")
    }

    // MARK: - BackendAPI.HookRequest Encoding Tests

    func testHookRequestEncodingWithAllFields() throws {
        let request = BackendAPI.HookRequest(
            filePath: "/path/to/song.mp3",
            artist: "Test Artist",
            title: "Test Track"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["file_path"] as? String, "/path/to/song.mp3")
        XCTAssertEqual(json?["artist"] as? String, "Test Artist")
        XCTAssertEqual(json?["title"] as? String, "Test Track")
    }

    func testHookRequestEncodingWithNilOptionals() throws {
        let request = BackendAPI.HookRequest(filePath: "/test.mp3")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["file_path"] as? String, "/test.mp3")
        // Optional nils are omitted from encoded JSON
        XCTAssertNil(json?["artist"])
        XCTAssertNil(json?["title"])
    }

    // MARK: - BackendAPI.HookResponse Decoding Tests

    func testHookResponseDecodingWithAllFields() throws {
        let json = """
        {
            "hook": "Let the music play",
            "confidence": 0.92,
            "occurrences": 4,
            "transcription": "Full transcription text here",
            "lyrics_verified": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.HookResponse.self, from: json)

        XCTAssertEqual(response.hook, "Let the music play")
        XCTAssertEqual(response.confidence, 0.92)
        XCTAssertEqual(response.occurrences, 4)
        XCTAssertEqual(response.transcription, "Full transcription text here")
        XCTAssertEqual(response.lyricsVerified, true)
    }

    func testHookResponseDecodingWithNullHook() throws {
        let json = """
        {
            "hook": null,
            "confidence": 0.0,
            "occurrences": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.HookResponse.self, from: json)

        XCTAssertNil(response.hook)
        XCTAssertEqual(response.confidence, 0.0)
        XCTAssertEqual(response.occurrences, 0)
        XCTAssertNil(response.transcription)
        XCTAssertNil(response.lyricsVerified)
    }

    func testHookResponseDecodingWithMissingOptionals() throws {
        let json = """
        {
            "confidence": 0.75,
            "occurrences": 2
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.HookResponse.self, from: json)

        XCTAssertNil(response.hook)
        XCTAssertEqual(response.confidence, 0.75)
        XCTAssertEqual(response.occurrences, 2)
        XCTAssertNil(response.transcription)
        XCTAssertNil(response.lyricsVerified)
    }

    func testHookResponseDecodingLyricsVerifiedFalse() throws {
        let json = """
        {
            "hook": "Verified hook",
            "confidence": 0.88,
            "occurrences": 3,
            "lyrics_verified": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.HookResponse.self, from: json)

        XCTAssertEqual(response.hook, "Verified hook")
        XCTAssertEqual(response.lyricsVerified, false)
    }
}
