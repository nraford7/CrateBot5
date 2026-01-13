import XCTest
@testable import CrateBotCore

final class VibeGeneratorTests: XCTestCase {

    // MARK: - VibeResult Tests

    func testVibeResultInitialization() {
        let result = VibeResult(
            vibe: "Late Night",
            description: "A smooth, atmospheric track",
            hook: "Feel the bass",
            hookConfidence: 0.85,
            scene: "Underground Club",
            sceneConfidence: 0.92,
            cached: false
        )

        XCTAssertEqual(result.vibe, "Late Night")
        XCTAssertEqual(result.description, "A smooth, atmospheric track")
        XCTAssertEqual(result.hook, "Feel the bass")
        XCTAssertEqual(result.hookConfidence, 0.85)
        XCTAssertEqual(result.scene, "Underground Club")
        XCTAssertEqual(result.sceneConfidence, 0.92)
        XCTAssertFalse(result.cached)
    }

    func testVibeResultWithDefaults() {
        let result = VibeResult(vibe: "Peak Time")

        XCTAssertEqual(result.vibe, "Peak Time")
        XCTAssertNil(result.description)
        XCTAssertNil(result.hook)
        XCTAssertNil(result.hookConfidence)
        XCTAssertNil(result.scene)
        XCTAssertNil(result.sceneConfidence)
        XCTAssertFalse(result.cached)
    }

    func testVibeResultCached() {
        let result = VibeResult(vibe: "Warm Up", cached: true)

        XCTAssertEqual(result.vibe, "Warm Up")
        XCTAssertTrue(result.cached)
    }

    // MARK: - VibeRequest Encoding Tests

    func testVibeRequestEncodingSnakeCase() throws {
        let request = BackendAPI.VibeRequest(
            filePath: "/path/to/track.mp3",
            overwrite: true,
            dryRun: false,
            skipHook: true
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["file_path"] as? String, "/path/to/track.mp3")
        XCTAssertEqual(json?["overwrite"] as? Bool, true)
        XCTAssertEqual(json?["dry_run"] as? Bool, false)
        XCTAssertEqual(json?["skip_hook"] as? Bool, true)
    }

    func testVibeRequestDefaults() throws {
        let request = BackendAPI.VibeRequest(filePath: "/test.mp3")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["file_path"] as? String, "/test.mp3")
        XCTAssertEqual(json?["overwrite"] as? Bool, false)
        XCTAssertEqual(json?["dry_run"] as? Bool, false)
        XCTAssertEqual(json?["skip_hook"] as? Bool, false)
    }

    // MARK: - VibeResponse Decoding Tests

    func testVibeResponseDecodingFromSnakeCase() throws {
        let json = """
        {
            "file_path": "/music/track.mp3",
            "filename": "track.mp3",
            "status": "tagged",
            "vibe": "Deep & Hypnotic",
            "description": "A mesmerizing journey through sound",
            "scene": "After Hours",
            "scene_confidence": 0.88,
            "hook": "Drop the beat",
            "hook_occurrences": 3,
            "detections": null,
            "error": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.VibeResponse.self, from: json)

        XCTAssertEqual(response.filePath, "/music/track.mp3")
        XCTAssertEqual(response.filename, "track.mp3")
        XCTAssertEqual(response.status, "tagged")
        XCTAssertEqual(response.vibe, "Deep & Hypnotic")
        XCTAssertEqual(response.description, "A mesmerizing journey through sound")
        XCTAssertEqual(response.scene, "After Hours")
        XCTAssertEqual(response.sceneConfidence, 0.88)
        XCTAssertEqual(response.hook, "Drop the beat")
        XCTAssertEqual(response.hookOccurrences, 3)
        XCTAssertNil(response.detections)
        XCTAssertNil(response.error)
    }

    func testVibeResponseDecodingMinimalFields() throws {
        let json = """
        {
            "file_path": "/test.mp3",
            "filename": "test.mp3",
            "status": "failed",
            "error": "File not found"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.VibeResponse.self, from: json)

        XCTAssertEqual(response.filePath, "/test.mp3")
        XCTAssertEqual(response.status, "failed")
        XCTAssertNil(response.vibe)
        XCTAssertNil(response.description)
        XCTAssertEqual(response.error, "File not found")
    }

    // MARK: - HookRequest/HookResponse Tests

    func testHookRequestEncoding() throws {
        let request = BackendAPI.HookRequest(
            filePath: "/path/to/song.mp3",
            artist: "Test Artist",
            title: "Test Track"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["file_path"] as? String, "/path/to/song.mp3")
        XCTAssertEqual(json?["artist"] as? String, "Test Artist")
        XCTAssertEqual(json?["title"] as? String, "Test Track")
    }

    func testHookRequestEncodingWithNils() throws {
        let request = BackendAPI.HookRequest(filePath: "/test.mp3")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["file_path"] as? String, "/test.mp3")
        // Nil values are omitted by default JSONEncoder (encodeIfPresent behavior)
        // The API should handle missing keys as null
        XCTAssertNil(json?["artist"])
        XCTAssertNil(json?["title"])
    }

    func testHookResponseDecoding() throws {
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

    func testHookResponseDecodingWithNils() throws {
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

    // MARK: - HTTPError Tests

    func testHTTPErrorDescriptions() {
        let invalidURL = HTTPError.invalidURL
        XCTAssertEqual(invalidURL.errorDescription, "Invalid URL")

        let requestFailed = HTTPError.requestFailed(statusCode: 404, message: "Not found")
        XCTAssertTrue(requestFailed.errorDescription?.contains("404") ?? false)
        XCTAssertTrue(requestFailed.errorDescription?.contains("Not found") ?? false)

        let decodingFailed = HTTPError.decodingFailed("Bad JSON")
        XCTAssertTrue(decodingFailed.errorDescription?.contains("decode") ?? false)
        XCTAssertTrue(decodingFailed.errorDescription?.contains("Bad JSON") ?? false)

        let networkFailed = HTTPError.networkError("Timeout")
        XCTAssertTrue(networkFailed.errorDescription?.contains("Network") ?? false)
        XCTAssertTrue(networkFailed.errorDescription?.contains("Timeout") ?? false)

        let serverNotRunning = HTTPError.serverNotRunning
        XCTAssertTrue(serverNotRunning.errorDescription?.contains("not running") ?? false)
    }

    // MARK: - VibeError Tests

    func testVibeErrorDescriptions() {
        let backendUnavailable = VibeError.backendUnavailable
        XCTAssertTrue(backendUnavailable.errorDescription?.contains("not available") ?? false)

        let generationFailed = VibeError.generationFailed("Test error message")
        XCTAssertTrue(generationFailed.errorDescription?.contains("Test error message") ?? false)

        let apiKeyNotConfigured = VibeError.apiKeyNotConfigured
        XCTAssertTrue(apiKeyNotConfigured.errorDescription?.contains("API key") ?? false)

        let invalidFile = VibeError.invalidFile("File not found")
        XCTAssertTrue(invalidFile.errorDescription?.contains("Invalid file") ?? false)
        XCTAssertTrue(invalidFile.errorDescription?.contains("File not found") ?? false)

        let apiKeyFailed = VibeError.apiKeyFailed("Connection refused")
        XCTAssertTrue(apiKeyFailed.errorDescription?.contains("Failed to set API key") ?? false)
        XCTAssertTrue(apiKeyFailed.errorDescription?.contains("Connection refused") ?? false)
    }

    // MARK: - HealthResponse Tests

    func testHealthResponseDecoding() throws {
        let json = """
        {
            "status": "ok",
            "model_loaded": true,
            "model_loading": false,
            "tag_manager_ready": true,
            "tag_manager_error": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.HealthResponse.self, from: json)

        XCTAssertEqual(response.status, "ok")
        XCTAssertTrue(response.modelLoaded)
        XCTAssertEqual(response.modelLoading, false)
        XCTAssertEqual(response.tagManagerReady, true)
        XCTAssertNil(response.tagManagerError)
    }

    // MARK: - SettingsResponse Tests

    func testSettingsResponseDecoding() throws {
        let json = """
        {
            "anthropic_api_key_set": true,
            "models_directory": "/Users/test/.cratebot/models",
            "cache_directory": "/Users/test/.cratebot/cache",
            "vibe_available": true,
            "vibe_status": "Available",
            "hook_available": true,
            "hook_status": "Whisper ready",
            "panns_available": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.SettingsResponse.self, from: json)

        XCTAssertTrue(response.anthropicApiKeySet)
        XCTAssertEqual(response.modelsDirectory, "/Users/test/.cratebot/models")
        XCTAssertEqual(response.cacheDirectory, "/Users/test/.cratebot/cache")
        XCTAssertTrue(response.vibeAvailable)
        XCTAssertEqual(response.vibeStatus, "Available")
        XCTAssertTrue(response.hookAvailable)
        XCTAssertEqual(response.hookStatus, "Whisper ready")
        XCTAssertEqual(response.pannsAvailable, false)
    }

    // MARK: - APIKeyRequest Tests

    func testAPIKeyRequestEncoding() throws {
        let request = BackendAPI.APIKeyRequest(apiKey: "sk-test-key-12345")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["api_key"] as? String, "sk-test-key-12345")
    }
}
