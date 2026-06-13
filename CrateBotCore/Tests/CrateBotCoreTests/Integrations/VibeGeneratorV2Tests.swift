import XCTest
@testable import CrateBotCore

final class VibeGeneratorV2Tests: XCTestCase {

    // MARK: - Mock clients

    /// Returns a canned reply, no spying.
    private final class MockClient: VibeChatClient, @unchecked Sendable {
        let reply: String
        init(reply: String) { self.reply = reply }
        func complete(
            prompt: String,
            system: String,
            maxTokens: Int,
            temperature: Double,
            model: String
        ) async throws -> String {
            return reply
        }
    }

    /// Records the last invocation parameters so tests can assert on them.
    private final class SpyClient: VibeChatClient, @unchecked Sendable {
        var reply: String = #"{"short":"X","long":"Y"}"#
        var lastPrompt: String?
        var lastSystem: String?
        var lastMaxTokens: Int?
        var lastTemperature: Double?
        var lastModel: String?
        func complete(
            prompt: String,
            system: String,
            maxTokens: Int,
            temperature: Double,
            model: String
        ) async throws -> String {
            lastPrompt = prompt
            lastSystem = system
            lastMaxTokens = maxTokens
            lastTemperature = temperature
            lastModel = model
            return reply
        }
    }

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

    /// Inputs where mix-hint is allowed: stage2 confidence > 0.5 AND cooccurrence != nil.
    private var sampleInputsWithMixHintAllowed: VibeGenerationInputs {
        VibeGenerationInputs(
            binaryConfidences: ["Dark": 0.8, "Hypnotic": 0.6],
            groupProbabilities: ["BassType": ["Sub Bass": 0.7]],
            predictedTags: makePredictions(),
            bpm: 124,
            key: "Am",
            durationSeconds: 360,
            title: "Test",
            artist: "Artist",
            stage2Timing: TimingPrediction(label: "Peak", confidence: 0.81),
            cooccurrence: CooccurrenceContext(
                timingLabel: "Peak",
                coOccurringTags: ["Dark", "Hypnotic"],
                support: 250
            )
        )
    }

    /// Default sample inputs (no cooccurrence → mix hint gated off).
    private var sampleInputs: VibeGenerationInputs {
        VibeGenerationInputs(
            binaryConfidences: ["Dark": 0.8],
            groupProbabilities: [:],
            predictedTags: makePredictions(),
            bpm: 124,
            key: "Am",
            durationSeconds: 360,
            title: "Test",
            artist: "Artist",
            stage2Timing: TimingPrediction(label: "Peak", confidence: 0.81),
            cooccurrence: nil
        )
    }

    /// Inputs where Stage 2 confidence is below the mix-hint threshold (0.5).
    private var sampleInputsLowConfidence: VibeGenerationInputs {
        VibeGenerationInputs(
            binaryConfidences: ["Dark": 0.8],
            groupProbabilities: [:],
            predictedTags: makePredictions(),
            bpm: 124,
            key: "Am",
            durationSeconds: 360,
            title: "Test",
            artist: "Artist",
            stage2Timing: TimingPrediction(label: "Peak", confidence: 0.40),
            cooccurrence: CooccurrenceContext(
                timingLabel: "Peak",
                coOccurringTags: ["Dark"],
                support: 100
            )
        )
    }

    // MARK: - Tests

    func testValidJSONResponseProducesAllThreeFields() async throws {
        let mock = MockClient(
            reply: #"{"short":"Late Night Groove","long":"sustained, low-lit","mix_hint":"sits between Peak and Release"}"#
        )
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputsWithMixHintAllowed)
        XCTAssertEqual(r.short, "Late Night Groove")
        XCTAssertEqual(r.long, "sustained, low-lit")
        XCTAssertEqual(r.mixHint, "sits between Peak and Release")
    }

    func testNoJSONInResponseIsRejected() async {
        // Reply contains no `{` at all — the brace extractor returns nil and
        // the generator must throw `parsingFailed`. This is the actual contract
        // exercised here; the prior name ("ChainOfThoughtPreambleIsRejected")
        // mis-described the input.
        let mock = MockClient(reply: "LOOKING AT THIS TRACK ANALYSIS: this is peak\nVIBE: Peak Roller")
        let gen = VibeGeneratorV2(client: mock)
        do {
            _ = try await gen.generate(inputs: sampleInputs)
            XCTFail("Expected parsingFailed error")
        } catch let error as VibeGeneratorError {
            switch error {
            case .parsingFailed: break
            default: XCTFail("Expected parsingFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected VibeGeneratorError.parsingFailed, got \(error)")
        }
    }

    func testValidJSONAfterCoTPreambleIsAccepted() async throws {
        // Real chain-of-thought preamble followed by valid JSON: the safety
        // net extracts the first balanced `{...}` regardless of leading prose.
        let reply = """
        LOOKING AT THIS TRACK ANALYSIS: peak-time, hypnotic, sub-bass driven.
        {"short":"X","long":"Y"}
        """
        let mock = MockClient(reply: reply)
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputs)
        XCTAssertEqual(r.short, "X")
        XCTAssertEqual(r.long, "Y")
    }

    func testExtractFirstJSONObjectHandlesBracesInsideStringLiterals() async throws {
        // Braces inside JSON string literals must not confuse the depth counter.
        // Without the string-aware brace tracking, `{a brace}` would close the
        // outer object early and the decode would fail.
        let mock = MockClient(
            reply: #"{"long":"has {a brace} inside","short":"X"}"#
        )
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputs)
        XCTAssertEqual(r.short, "X")
        XCTAssertEqual(r.long, "has {a brace} inside")
    }

    func testProseWrappedJSONIsExtracted() async throws {
        let reply = """
        Here's the analysis:
        ```json
        {"short":"Late Night Groove","long":"sustained, low-lit","mix_hint":"sits between Peak and Release"}
        ```
        Let me know if you'd like adjustments.
        """
        let mock = MockClient(reply: reply)
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputsWithMixHintAllowed)
        XCTAssertEqual(r.short, "Late Night Groove")
        XCTAssertEqual(r.long, "sustained, low-lit")
        XCTAssertEqual(r.mixHint, "sits between Peak and Release")
    }

    func testMixHintOmittedWhenInputsHaveNoCooccurrence() async throws {
        // cooccurrence == nil → mix-hint gate closed.
        let mock = MockClient(reply: #"{"short":"X","long":"Y"}"#)
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputs)
        XCTAssertEqual(r.short, "X")
        XCTAssertEqual(r.long, "Y")
        XCTAssertNil(r.mixHint)
    }

    func testMixHintGateBelowStage2Confidence() async throws {
        // confidence < 0.5 → gate closed even though cooccurrence present.
        // Generator should also drop mix_hint from the result even if model returns one.
        let mock = MockClient(reply: #"{"short":"X","long":"Y","mix_hint":"unwanted"}"#)
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputsLowConfidence)
        XCTAssertEqual(r.short, "X")
        XCTAssertEqual(r.long, "Y")
        XCTAssertNil(r.mixHint, "Mix hint should be dropped when Stage 2 confidence ≤ 0.5")
    }

    func testTemperatureAndModelMatchSpec() async {
        let spy = SpyClient()
        let gen = VibeGeneratorV2(client: spy)
        _ = try? await gen.generate(inputs: sampleInputs)
        XCTAssertEqual(spy.lastTemperature ?? 0, 0.7, accuracy: 0.001)
        XCTAssertEqual(spy.lastModel, AnthropicClient.defaultModel)
    }
}
