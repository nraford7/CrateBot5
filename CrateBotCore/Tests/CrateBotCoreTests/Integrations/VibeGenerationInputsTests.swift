import XCTest
@testable import CrateBotCore

final class VibeGenerationInputsTests: XCTestCase {

    // MARK: - Fixtures

    private func makePredictions() -> UserTagPredictions {
        UserTagPredictions(
            genre: "House",
            timing: "Peak",
            mood: "Dark",
            bassType: "Sub Bass",
            rhythm: ["4-on-the-floor"],
            style: ["Driving"],
            vibes: ["Hypnotic"],
            instruments: ["Synth"],
            vocalType: nil,
            acapella: false,
            customTags: []
        )
    }

    private func makeInputs(
        bpm: Float? = 124.0,
        key: String? = "Am",
        title: String? = "Test Track",
        artist: String? = "Test Artist",
        album: String? = "Test Album",
        stage2Timing: TimingPrediction? = TimingPrediction(label: "Peak", confidence: 0.81),
        cooccurrence: CooccurrenceContext? = CooccurrenceContext(
            timingLabel: "Peak",
            coOccurringTags: ["Dark", "Hypnotic"],
            support: 250
        )
    ) -> VibeGenerationInputs {
        VibeGenerationInputs(
            binaryConfidences: ["Dark": 0.876543, "Hypnotic": 0.5, "Driving": 0.123456],
            groupProbabilities: [
                "BassType": ["Sub Bass": 0.7, "Reese": 0.2],
                "VocalType": ["None": 0.9]
            ],
            predictedTags: makePredictions(),
            bpm: bpm,
            key: key,
            durationSeconds: 360.5,
            title: title,
            artist: artist,
            album: album,
            stage2Timing: stage2Timing,
            cooccurrence: cooccurrence
        )
    }

    // MARK: - Round-trip

    func testRoundTripFields() {
        let inputs = makeInputs()
        XCTAssertEqual(inputs.binaryConfidences["Dark"], 0.876543)
        XCTAssertEqual(inputs.groupProbabilities["BassType"]?["Sub Bass"], 0.7)
        XCTAssertEqual(inputs.predictedTags.genre, "House")
        XCTAssertEqual(inputs.predictedTags.timing, "Peak")
        XCTAssertEqual(inputs.bpm, 124.0)
        XCTAssertEqual(inputs.key, "Am")
        XCTAssertEqual(inputs.durationSeconds, 360.5)
        XCTAssertEqual(inputs.title, "Test Track")
        XCTAssertEqual(inputs.artist, "Test Artist")
        XCTAssertEqual(inputs.album, "Test Album")
        XCTAssertEqual(inputs.stage2Timing?.label, "Peak")
        XCTAssertEqual(inputs.stage2Timing?.confidence, 0.81)
        XCTAssertEqual(inputs.cooccurrence?.coOccurringTags, ["Dark", "Hypnotic"])
    }

    // MARK: - promptPayload determinism

    func testPromptPayloadIsDeterministic() {
        let inputs = makeInputs()
        let a = inputs.promptPayload()
        let b = inputs.promptPayload()
        XCTAssertEqual(a, b, "promptPayload() must be byte-identical across calls")
    }

    func testPromptPayloadIsByteIdenticalAcrossEquivalentDicts() {
        // Same fields, different in-memory dict order — payload should match.
        let inputs1 = VibeGenerationInputs(
            binaryConfidences: ["Dark": 0.5, "Hypnotic": 0.7],
            groupProbabilities: [:],
            predictedTags: makePredictions(),
            bpm: 124,
            key: "Am",
            durationSeconds: 300,
            title: nil,
            artist: nil,
            album: nil,
            stage2Timing: nil,
            cooccurrence: nil
        )
        let inputs2 = VibeGenerationInputs(
            binaryConfidences: ["Hypnotic": 0.7, "Dark": 0.5],
            groupProbabilities: [:],
            predictedTags: makePredictions(),
            bpm: 124,
            key: "Am",
            durationSeconds: 300,
            title: nil,
            artist: nil,
            album: nil,
            stage2Timing: nil,
            cooccurrence: nil
        )
        XCTAssertEqual(inputs1.promptPayload(), inputs2.promptPayload())
    }

    // MARK: - Rounding

    func testPromptPayloadRoundsConfidencesTo3DecimalPlaces() {
        let inputs = makeInputs()
        let payload = inputs.promptPayload()
        // 0.876543 → exact "0.877" (no Float→Double promotion noise like 0.8770000338554382).
        // We assert the EXACT substring boundary (`,` or `}`) to catch any promotion regression.
        XCTAssertTrue(
            payload.contains("\"Dark\":0.877,") || payload.contains("\"Dark\":0.877}"),
            "Expected exact \"Dark\":0.877 (no trailing precision) in payload, got: \(payload)"
        )
        // 0.123456 → exact "0.123"
        XCTAssertTrue(
            payload.contains("\"Driving\":0.123,") || payload.contains("\"Driving\":0.123}"),
            "Expected exact \"Driving\":0.123 in payload, got: \(payload)"
        )
        // No raw 6-digit precision and no Float-promotion artifacts should leak through.
        XCTAssertFalse(payload.contains("0.876543"))
        XCTAssertFalse(payload.contains("0.123456"))
        XCTAssertFalse(payload.contains("0.8770000"), "Float→Double promotion leaked into payload: \(payload)")
        XCTAssertFalse(payload.contains("0.1230000"), "Float→Double promotion leaked into payload: \(payload)")
    }

    // MARK: - NaN / Inf sanitization

    func testPromptPayloadSanitizesNaNToZero() {
        // A NaN bpm or confidence used to silently swallow the entire payload into "{}"
        // because nonConformingFloatEncodingStrategy = .throw fired and try? returned nil.
        // round3 now sanitizes NaN/Inf to 0.0 so the encoder never sees a non-conforming value.
        let inputs = VibeGenerationInputs(
            binaryConfidences: ["Dark": Float.nan, "Hypnotic": 0.5],
            groupProbabilities: ["BassType": ["Sub Bass": Float.infinity]],
            predictedTags: makePredictions(),
            bpm: Float.nan,
            key: "Am",
            durationSeconds: 300,
            title: nil,
            artist: nil,
            album: nil,
            stage2Timing: TimingPrediction(label: "Peak", confidence: Float.nan),
            cooccurrence: nil
        )
        let payload = inputs.promptPayload()
        XCTAssertNotEqual(payload, "{}", "NaN must not silently produce empty payload")
        // NaN-cleaned values should appear as 0
        XCTAssertTrue(payload.contains("\"Dark\":0"), "Expected NaN Dark → 0 in payload, got: \(payload)")
        XCTAssertTrue(payload.contains("\"bpm\":0"), "Expected NaN bpm → 0 in payload, got: \(payload)")
        XCTAssertTrue(payload.contains("\"Sub Bass\":0"), "Expected Inf Sub Bass → 0 in payload, got: \(payload)")
        XCTAssertTrue(payload.contains("\"confidence\":0"), "Expected NaN stage2Timing.confidence → 0 in payload, got: \(payload)")
        // Non-NaN sibling should still round normally
        XCTAssertTrue(payload.contains("\"Hypnotic\":0.5"))
        // No raw NaN/Infinity tokens leaked
        XCTAssertFalse(payload.lowercased().contains("nan"))
        XCTAssertFalse(payload.lowercased().contains("inf"))
    }

    func testPromptPayloadRoundsGroupProbabilitiesTo3DecimalPlaces() {
        let inputs = VibeGenerationInputs(
            binaryConfidences: [:],
            groupProbabilities: ["BassType": ["Sub Bass": 0.123456]],
            predictedTags: makePredictions(),
            bpm: nil,
            key: nil,
            durationSeconds: 0,
            title: nil,
            artist: nil,
            album: nil,
            stage2Timing: nil,
            cooccurrence: nil
        )
        let payload = inputs.promptPayload()
        XCTAssertTrue(payload.contains("0.123"))
        XCTAssertFalse(payload.contains("0.123456"))
    }

    // MARK: - Sorted keys

    func testPromptPayloadHasSortedKeys() {
        let inputs = makeInputs()
        let payload = inputs.promptPayload()
        // Top-level keys should appear in sorted order. "artist" < "binaryConfidences" < "bpm" ...
        guard let artistIdx = payload.range(of: "\"artist\"")?.lowerBound,
              let bpmIdx = payload.range(of: "\"bpm\"")?.lowerBound else {
            XCTFail("Expected both keys in payload")
            return
        }
        XCTAssertLessThan(artistIdx, bpmIdx, "Keys should be sorted: artist before bpm")
    }

    // MARK: - Omits nil optional context fields

    func testPromptPayloadOmitsStage2TimingWhenNil() {
        let inputs = makeInputs(stage2Timing: nil)
        let payload = inputs.promptPayload()
        XCTAssertFalse(payload.contains("stage2Timing"),
                       "Expected stage2Timing key to be absent when nil, got: \(payload)")
        XCTAssertFalse(payload.contains("\"null\""))
    }

    func testPromptPayloadOmitsCooccurrenceWhenNil() {
        let inputs = makeInputs(cooccurrence: nil)
        let payload = inputs.promptPayload()
        XCTAssertFalse(payload.contains("cooccurrence"),
                       "Expected cooccurrence key to be absent when nil, got: \(payload)")
    }

    func testPromptPayloadIncludesStage2TimingWhenPresent() {
        let inputs = makeInputs()
        let payload = inputs.promptPayload()
        XCTAssertTrue(payload.contains("stage2Timing"))
        XCTAssertTrue(payload.contains("Peak"))
    }

    func testPromptPayloadIncludesCooccurrenceWhenPresent() {
        let inputs = makeInputs()
        let payload = inputs.promptPayload()
        XCTAssertTrue(payload.contains("cooccurrence"))
        XCTAssertTrue(payload.contains("coOccurringTags"))
    }

    func testPromptPayloadIncludesAlbumWhenPresent() {
        let inputs = makeInputs(album: "Night Glass")
        let payload = inputs.promptPayload()
        XCTAssertTrue(payload.contains("\"album\":\"Night Glass\""))
    }
}
