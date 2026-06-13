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
            stage2Timing: nil,
            cooccurrence: nil
        )
        XCTAssertEqual(inputs1.promptPayload(), inputs2.promptPayload())
    }

    // MARK: - Rounding

    func testPromptPayloadRoundsConfidencesTo3DecimalPlaces() {
        let inputs = makeInputs()
        let payload = inputs.promptPayload()
        // 0.876543 → "0.877" (standard half-up rounding)
        XCTAssertTrue(
            payload.contains("\"Dark\":0.877"),
            "Expected 0.877 (rounded) in payload, got: \(payload)"
        )
        // 0.123456 → "0.123"
        XCTAssertTrue(
            payload.contains("\"Driving\":0.123"),
            "Expected 0.123 in payload, got: \(payload)"
        )
        // No raw 6-digit precision should leak through.
        XCTAssertFalse(payload.contains("0.876543"))
        XCTAssertFalse(payload.contains("0.123456"))
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
}
