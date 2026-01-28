import XCTest
@testable import CrateBotCore

final class NativeHookDetectorTests: XCTestCase {

    // MARK: - HookResult Initialization Tests

    func testHookResultInitialization() {
        let result = HookResult(
            hook: "Drop it low",
            confidence: 0.85,
            occurrences: 4,
            transcription: "Drop it low drop it low"
        )

        XCTAssertEqual(result.hook, "Drop it low")
        XCTAssertEqual(result.confidence, 0.85)
        XCTAssertEqual(result.occurrences, 4)
        XCTAssertEqual(result.transcription, "Drop it low drop it low")
    }

    func testHookResultWithNilValues() {
        let result = HookResult(
            hook: nil,
            confidence: 0.0,
            occurrences: 0,
            transcription: nil
        )

        XCTAssertNil(result.hook)
        XCTAssertEqual(result.confidence, 0.0)
        XCTAssertEqual(result.occurrences, 0)
        XCTAssertNil(result.transcription)
    }

    // MARK: - HookResult.hasHook Tests

    func testHasHookReturnsFalseWhenNoHook() {
        let result = HookResult(
            hook: nil,
            confidence: 0.9,
            occurrences: 5,
            transcription: "Some text"
        )

        XCTAssertFalse(result.hasHook, "hasHook should return false when hook is nil")
    }

    func testHasHookReturnsFalseWithLowConfidence() {
        let result = HookResult(
            hook: "Got the beat",
            confidence: 0.4,
            occurrences: 3,
            transcription: "Got the beat"
        )

        XCTAssertFalse(result.hasHook, "hasHook should return false when confidence < 0.5")
    }

    func testHasHookReturnsTrueWithHighConfidence() {
        let result = HookResult(
            hook: "Feel the rhythm",
            confidence: 0.75,
            occurrences: 3,
            transcription: "Feel the rhythm"
        )

        XCTAssertTrue(result.hasHook, "hasHook should return true when hook exists and confidence >= 0.5")
    }

    func testHasHookReturnsTrueAtExactThreshold() {
        let result = HookResult(
            hook: "Let it go",
            confidence: 0.5,
            occurrences: 2,
            transcription: "Let it go"
        )

        XCTAssertTrue(result.hasHook, "hasHook should return true when confidence is exactly 0.5")
    }

    // MARK: - DetectedPhrase Tests

    func testDetectedPhraseInitialization() {
        let phrase = DetectedPhrase(
            phrase: "feel the beat",
            count: 3,
            confidence: 0.8
        )

        XCTAssertEqual(phrase.phrase, "feel the beat")
        XCTAssertEqual(phrase.count, 3)
        XCTAssertEqual(phrase.confidence, 0.8)
    }

    // MARK: - extractRepeatedPhrases Tests

    func testExtractRepeatedPhrasesWithRepeatedPhrases() {
        let text = "Feel the beat feel the beat drop the bass feel the beat"

        let phrases = NativeHookDetector.extractRepeatedPhrases(from: text)

        XCTAssertFalse(phrases.isEmpty, "Should detect repeated phrases")

        // "feel the beat" appears 3 times
        let feelTheBeat = phrases.first { $0.phrase == "feel the beat" }
        XCTAssertNotNil(feelTheBeat, "Should detect 'feel the beat' phrase")
        if let phrase = feelTheBeat {
            XCTAssertEqual(phrase.count, 3, "Should count 3 occurrences of 'feel the beat'")
        }
    }

    func testExtractRepeatedPhrasesWithNoRepeats() {
        let text = "Every word in this sentence is unique and different"

        let phrases = NativeHookDetector.extractRepeatedPhrases(from: text)

        XCTAssertTrue(phrases.isEmpty, "Should return empty array when no phrases repeat")
    }

    func testExtractRepeatedPhrasesIsCaseInsensitive() {
        let text = "Drop The Bass drop the bass DROP THE BASS"

        let phrases = NativeHookDetector.extractRepeatedPhrases(from: text)

        XCTAssertFalse(phrases.isEmpty, "Should detect repeated phrases regardless of case")

        let dropTheBass = phrases.first { $0.phrase == "drop the bass" }
        XCTAssertNotNil(dropTheBass, "Should find 'drop the bass' phrase")
        if let phrase = dropTheBass {
            XCTAssertEqual(phrase.count, 3, "Should count all case variations as one phrase")
        }
    }

    func testExtractRepeatedPhrasesSortedByConfidence() {
        // Create text where one phrase has higher confidence than another
        let text = "let me see you move let me see you move let me see you move hands up hands up"

        let phrases = NativeHookDetector.extractRepeatedPhrases(from: text)

        guard phrases.count >= 2 else {
            XCTFail("Should detect at least 2 repeated phrases")
            return
        }

        // Should be sorted by confidence (descending)
        for i in 0..<(phrases.count - 1) {
            XCTAssertGreaterThanOrEqual(
                phrases[i].confidence,
                phrases[i + 1].confidence,
                "Phrases should be sorted by confidence in descending order"
            )
        }
    }

    func testExtractRepeatedPhrasesReturnsMaxFive() {
        // Create text with many repeated phrases
        let text = """
        one two three one two three
        four five six four five six
        seven eight nine seven eight nine
        ten eleven twelve ten eleven twelve
        thirteen fourteen fifteen thirteen fourteen fifteen
        sixteen seventeen eighteen sixteen seventeen eighteen
        """

        let phrases = NativeHookDetector.extractRepeatedPhrases(from: text)

        XCTAssertLessThanOrEqual(phrases.count, 5, "Should return at most 5 phrases")
    }

    func testExtractRepeatedPhrasesRequiresMinTwoOccurrences() {
        let text = "one two three four five six seven eight nine"

        let phrases = NativeHookDetector.extractRepeatedPhrases(from: text)

        XCTAssertTrue(phrases.isEmpty, "Should not return phrases that only appear once")
    }

    // MARK: - NativeHookError Tests

    func testNativeHookErrorDescriptions() {
        let unavailableError = NativeHookError.speechRecognitionUnavailable
        XCTAssertNotNil(unavailableError.errorDescription)
        XCTAssertTrue(unavailableError.errorDescription?.lowercased().contains("speech") ?? false)

        let deniedError = NativeHookError.authorizationDenied
        XCTAssertNotNil(deniedError.errorDescription)
        XCTAssertTrue(deniedError.errorDescription?.lowercased().contains("authorization") ?? false)

        let noVocalsError = NativeHookError.noVocalsDetected
        XCTAssertNotNil(noVocalsError.errorDescription)
        XCTAssertTrue(noVocalsError.errorDescription?.lowercased().contains("vocals") ?? false)

        let transcriptionError = NativeHookError.transcriptionFailed("Test error")
        XCTAssertNotNil(transcriptionError.errorDescription)
        XCTAssertTrue(transcriptionError.errorDescription?.contains("Test error") ?? false)

        let fileNotFoundError = NativeHookError.fileNotFound("/test/path.mp3")
        XCTAssertNotNil(fileNotFoundError.errorDescription)
        XCTAssertTrue(fileNotFoundError.errorDescription?.contains("/test/path.mp3") ?? false)

        let audioLoadError = NativeHookError.audioLoadFailed("Cannot read file")
        XCTAssertNotNil(audioLoadError.errorDescription)
        XCTAssertTrue(audioLoadError.errorDescription?.contains("Cannot read file") ?? false)
    }
}
