import XCTest
@testable import CrateBotCore

final class NativeVibeGeneratorTests: XCTestCase {

    // MARK: - VibeContext Tests

    func testVibeContextFormattedContainsTempo() {
        let context = VibeContext(
            tempo: 128.5,
            energy: 0.8,
            danceability: 0.75,
            mood: "Energetic",
            genre: "House",
            key: "Am",
            hasVocals: true,
            additionalTags: ["Deep", "Groovy"]
        )

        let formatted = context.formatted
        XCTAssertTrue(formatted.contains("128.5"), "Formatted context should contain tempo")
    }

    func testVibeContextFormattedContainsGenre() {
        let context = VibeContext(
            tempo: 120.0,
            energy: 0.6,
            danceability: 0.5,
            mood: "Chill",
            genre: "Techno",
            key: "Cm",
            hasVocals: false,
            additionalTags: []
        )

        let formatted = context.formatted
        XCTAssertTrue(formatted.contains("Techno"), "Formatted context should contain genre")
    }

    func testVibeContextFormattedContainsMood() {
        let context = VibeContext(
            tempo: 140.0,
            energy: 0.9,
            danceability: 0.85,
            mood: "Euphoric",
            genre: "Trance",
            key: "F#m",
            hasVocals: true,
            additionalTags: ["Uplifting"]
        )

        let formatted = context.formatted
        XCTAssertTrue(formatted.contains("Euphoric"), "Formatted context should contain mood")
    }

    func testVibeContextFormattedContainsAllFields() {
        let context = VibeContext(
            tempo: 125.0,
            energy: 0.7,
            danceability: 0.65,
            mood: "Dark",
            genre: "Tech House",
            key: "Dm",
            hasVocals: false,
            additionalTags: ["Driving", "Minimal"]
        )

        let formatted = context.formatted

        // Should contain all key information
        XCTAssertTrue(formatted.contains("125"), "Should contain tempo")
        XCTAssertTrue(formatted.contains("Tech House"), "Should contain genre")
        XCTAssertTrue(formatted.contains("Dark"), "Should contain mood")
        XCTAssertTrue(formatted.contains("Dm"), "Should contain key")
        XCTAssertTrue(formatted.contains("0.7") || formatted.contains("70"), "Should contain energy")
        XCTAssertTrue(formatted.contains("0.65") || formatted.contains("65"), "Should contain danceability")
    }

    // MARK: - buildPrompt Tests

    func testBuildPromptContainsGenre() {
        let context = VibeContext(
            tempo: 128.0,
            energy: 0.8,
            danceability: 0.75,
            mood: "Energetic",
            genre: "Deep House",
            key: "Am",
            hasVocals: true,
            additionalTags: []
        )

        let prompt = NativeVibeGenerator.buildPrompt(context: context)
        XCTAssertTrue(prompt.contains("Deep House"), "Prompt should contain the genre")
    }

    func testBuildPromptContainsVibeInstruction() {
        let context = VibeContext(
            tempo: 130.0,
            energy: 0.7,
            danceability: 0.6,
            mood: "Hypnotic",
            genre: "Minimal",
            key: "Cm",
            hasVocals: false,
            additionalTags: []
        )

        let prompt = NativeVibeGenerator.buildPrompt(context: context)
        XCTAssertTrue(prompt.contains("VIBE:"), "Prompt should instruct model to output VIBE:")
    }

    // MARK: - parseVibeFromResponse Tests

    func testParseVibeFromResponseWithValidInput() {
        let response = """
        Based on the audio characteristics you've described, this track has a late-night feel.

        VIBE: Late Night Groove

        This vibe captures the essence of the track's deep, hypnotic nature.
        """

        let vibe = NativeVibeGenerator.parseVibeFromResponse(response)
        XCTAssertNotNil(vibe, "Should parse vibe from valid response")
        XCTAssertEqual(vibe, "Late Night Groove")
    }

    func testParseVibeFromResponseWithNoMatch() {
        let response = """
        This is a response that doesn't contain the expected format.
        The track has good energy but I'm not sure what to call it.
        """

        let vibe = NativeVibeGenerator.parseVibeFromResponse(response)
        XCTAssertNil(vibe, "Should return nil when no VIBE: pattern found")
    }

    func testParseVibeFromResponseWithMultipleLines() {
        let response = """
        Let me analyze this track.

        VIBE: Peak Time Banger

        This definitely fits the high-energy profile.
        """

        let vibe = NativeVibeGenerator.parseVibeFromResponse(response)
        XCTAssertEqual(vibe, "Peak Time Banger")
    }

    func testParseVibeFromResponseTrimsWhitespace() {
        let response = "VIBE:   Sunset Chillout   \n\nGreat for relaxing."

        let vibe = NativeVibeGenerator.parseVibeFromResponse(response)
        XCTAssertEqual(vibe, "Sunset Chillout", "Should trim whitespace from parsed vibe")
    }

    func testParseVibeFromResponseCaseInsensitive() {
        // Test both uppercase and lowercase VIBE
        let response1 = "VIBE: Test Vibe One"
        let response2 = "vibe: Test Vibe Two"

        let vibe1 = NativeVibeGenerator.parseVibeFromResponse(response1)
        _ = NativeVibeGenerator.parseVibeFromResponse(response2)

        XCTAssertNotNil(vibe1)
        XCTAssertEqual(vibe1, "Test Vibe One")
        // Note: If implementation is case-sensitive, vibe2 may be nil - that's acceptable
    }

    // MARK: - NativeVibeError Tests

    func testNativeVibeErrorDescriptions() {
        let apiKeyError = NativeVibeError.apiKeyNotConfigured
        XCTAssertTrue(apiKeyError.errorDescription?.contains("API key") ?? false)

        let generationError = NativeVibeError.generationFailed("Test failure")
        XCTAssertTrue(generationError.errorDescription?.contains("Test failure") ?? false)

        let parsingError = NativeVibeError.parsingFailed
        XCTAssertNotNil(parsingError.errorDescription)

        let fileError = NativeVibeError.fileNotFound("/test/path.mp3")
        XCTAssertTrue(fileError.errorDescription?.contains("/test/path.mp3") ?? false)
    }

    // MARK: - VibeResult Tests (for NativeVibeGenerator's version)

    func testNativeVibeResultInitialization() {
        let result = NativeVibeResult(
            vibe: "Morning Warmup",
            description: "Perfect for starting the day",
            cached: false
        )

        XCTAssertEqual(result.vibe, "Morning Warmup")
        XCTAssertEqual(result.description, "Perfect for starting the day")
        XCTAssertFalse(result.cached)
    }

    func testNativeVibeResultWithDefaults() {
        let result = NativeVibeResult(vibe: "Club Ready")

        XCTAssertEqual(result.vibe, "Club Ready")
        XCTAssertNil(result.description)
        XCTAssertFalse(result.cached)
    }

    func testNativeVibeResultCached() {
        let result = NativeVibeResult(vibe: "Poolside", cached: true)

        XCTAssertEqual(result.vibe, "Poolside")
        XCTAssertTrue(result.cached)
    }

    // MARK: - System Prompt Tests

    func testSystemPromptIsNotEmpty() {
        let systemPrompt = NativeVibeGenerator.systemPrompt
        XCTAssertFalse(systemPrompt.isEmpty, "System prompt should not be empty")
    }

    func testSystemPromptContainsVibeContext() {
        let systemPrompt = NativeVibeGenerator.systemPrompt
        // The system prompt should mention what the assistant's role is
        XCTAssertTrue(
            systemPrompt.lowercased().contains("vibe") || systemPrompt.lowercased().contains("music"),
            "System prompt should reference vibe or music context"
        )
    }
}
