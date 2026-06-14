import XCTest
@testable import CrateBotCore

final class VibeGeneratorV2Tests: XCTestCase {

    // MARK: - Mock clients

    /// Returns canned replies in order.
    private final class MockClient: VibeChatClient, @unchecked Sendable {
        let replies: [String]
        var calls = 0

        init(replies: [String]) {
            self.replies = replies
        }

        convenience init(reply: String) {
            self.init(replies: [reply])
        }

        func complete(
            prompt: String,
            system: String,
            maxTokens: Int,
            temperature: Double,
            model: String
        ) async throws -> String {
            let idx = min(calls, max(0, replies.count - 1))
            calls += 1
            return replies[idx]
        }
    }

    /// Records invocation parameters so tests can assert on both generation passes.
    private final class SpyClient: VibeChatClient, @unchecked Sendable {
        var replies: [String] = [
            VibeGeneratorV2Tests.validDescriptionReply,
            VibeGeneratorV2Tests.validMovementReply
        ]
        var prompts: [String] = []
        var systems: [String] = []
        var maxTokens: [Int] = []
        var temperatures: [Double] = []
        var models: [String] = []

        func complete(
            prompt: String,
            system: String,
            maxTokens: Int,
            temperature: Double,
            model: String
        ) async throws -> String {
            prompts.append(prompt)
            systems.append(system)
            self.maxTokens.append(maxTokens)
            temperatures.append(temperature)
            models.append(model)
            let idx = min(prompts.count - 1, max(0, replies.count - 1))
            return replies[idx]
        }
    }

    /// Throws the same error for every request.
    private final class ThrowingClient: VibeChatClient, @unchecked Sendable {
        let error: Error

        init(error: Error) {
            self.error = error
        }

        func complete(
            prompt: String,
            system: String,
            maxTokens: Int,
            temperature: Double,
            model: String
        ) async throws -> String {
            throw error
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
            album: "Album",
            stage2Timing: TimingPrediction(label: "Peak", confidence: 0.81),
            cooccurrence: CooccurrenceContext(
                timingLabel: "Peak",
                coOccurringTags: ["Dark", "Hypnotic"],
                support: 250
            )
        )
    }

    /// Default sample inputs (no cooccurrence; movement is still generated).
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
            album: "Album",
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
            album: "Album",
            stage2Timing: TimingPrediction(label: "Peak", confidence: 0.40),
            cooccurrence: CooccurrenceContext(
                timingLabel: "Peak",
                coOccurringTags: ["Dark"],
                support: 100
            )
        )
    }

    // MARK: - Tests

    private struct DescriptionFixture: Encodable {
        let weight_options: [String]
        let texture_options: [String]
        let emotion_options: [String]
        let signature_options: [String]
        let long: String
    }

    private static func descriptionReply(
        weight: [String] = ["HEAVY", "SOLID", "PUNCHY"],
        texture: [String] = ["RUBBERY", "METALLIC", "GLASSY"],
        emotion: [String] = ["URGENT", "NASTY", "BRIGHT"],
        signature: [String] = ["ENGINE", "WIRE", "EMBER"],
        long: String = "Velvet pressure hangs in a rainlit stairwell, metallic edges brushing warm concrete."
    ) -> String {
        let fixture = DescriptionFixture(
            weight_options: weight,
            texture_options: texture,
            emotion_options: emotion,
            signature_options: signature,
            long: long
        )
        let data = try! JSONEncoder().encode(fixture)
        return String(data: data, encoding: .utf8)!
    }

    private static let validDescriptionReply = descriptionReply()

    private static let validMovementReply =
        #"{"mix_hint":"2AM bridge after rough drums before melodic release"}"#

    func testValidJSONResponseProducesAllThreeFields() async throws {
        let mock = MockClient(
            replies: [Self.validDescriptionReply, Self.validMovementReply]
        )
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputsWithMixHintAllowed)
        XCTAssertEqual(r.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(r.long, "Velvet pressure hangs in a rainlit stairwell, metallic edges brushing warm concrete.")
        XCTAssertEqual(r.mixHint, "2AM bridge after rough drums before melodic release")
        XCTAssertEqual(mock.calls, 2)
    }

    func testCancellationIsPropagated() async {
        let gen = VibeGeneratorV2(client: ThrowingClient(error: CancellationError()))

        do {
            _ = try await gen.generate(inputs: sampleInputs)
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: cancellation must stay cancellation, not become a
            // VibeGeneratorError.generationFailed row message.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testMissingAPIKeyHeaderMapsToAPIKeyNotConfigured() async {
        let gen = VibeGeneratorV2(
            client: ThrowingClient(
                error: AnthropicError.requestFailed(
                    statusCode: 401,
                    message: "x-api-key header is required"
                )
            )
        )

        do {
            _ = try await gen.generate(inputs: sampleInputs)
            XCTFail("Expected apiKeyNotConfigured")
        } catch let error as VibeGeneratorError {
            switch error {
            case .apiKeyNotConfigured: break
            default: XCTFail("Expected apiKeyNotConfigured, got \(error)")
            }
        } catch {
            XCTFail("Expected VibeGeneratorError.apiKeyNotConfigured, got \(error)")
        }
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
        \(Self.validDescriptionReply)
        """
        let mock = MockClient(replies: [reply, Self.validMovementReply])
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputs)
        XCTAssertEqual(r.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(r.long, "Velvet pressure hangs in a rainlit stairwell, metallic edges brushing warm concrete.")
    }

    func testExtractFirstJSONObjectHandlesBracesInsideStringLiterals() async throws {
        // Braces inside JSON string literals must not confuse the depth counter.
        // Without the string-aware brace tracking, `{a brace}` would close the
        // outer object early and the decode would fail.
        let long = "Velvet {pressure} hangs in a rainlit stairwell, metallic edges brushing warm concrete."
        let mock = MockClient(
            replies: [
                Self.descriptionReply(long: long),
                Self.validMovementReply
            ]
        )
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputs)
        XCTAssertEqual(r.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(r.long, long)
    }

    func testExtractFirstJSONObjectHandlesEscapedQuotesInsideStrings() async throws {
        // Escaped quotes inside a JSON string literal must not flip the parser
        // out of string-mode mid-token. If they did, the stray `}` inside the
        // string would close the outer object early and trim the value short.
        let long = #"Velvet "pressure" hangs in a rainlit stairwell, metallic edges brushing warm concrete }"#
        let mock = MockClient(
            replies: [
                Self.descriptionReply(long: long),
                Self.validMovementReply
            ]
        )
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputs)
        XCTAssertEqual(r.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(r.long, long)
    }

    func testProseWrappedJSONIsExtracted() async throws {
        let reply = """
        Here's the analysis:
        ```json
        \(Self.validDescriptionReply)
        ```
        Let me know if you'd like adjustments.
        """
        let mock = MockClient(replies: [reply, Self.validMovementReply])
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputsWithMixHintAllowed)
        XCTAssertEqual(r.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(r.long, "Velvet pressure hangs in a rainlit stairwell, metallic edges brushing warm concrete.")
        XCTAssertEqual(r.mixHint, "2AM bridge after rough drums before melodic release")
    }

    func testMissingMixHintIsRejected() async {
        let mock = MockClient(replies: [Self.validDescriptionReply, #"{"short":"IGNORED"}"#])
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

    func testMixHintReturnedRegardlessOfStage2Confidence() async throws {
        let mock = MockClient(replies: [Self.validDescriptionReply, Self.validMovementReply])
        let gen = VibeGeneratorV2(client: mock)
        let r = try await gen.generate(inputs: sampleInputsLowConfidence)
        XCTAssertEqual(r.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(r.long, "Velvet pressure hangs in a rainlit stairwell, metallic edges brushing warm concrete.")
        XCTAssertEqual(r.mixHint, "2AM bridge after rough drums before melodic release")
    }

    func testShortRejectsSourceTagRepeats() async {
        let badDescription = Self.descriptionReply(weight: ["HOUSE"])
        let mock = MockClient(replies: [badDescription, badDescription])
        let gen = VibeGeneratorV2(client: mock)
        do {
            _ = try await gen.generate(inputs: sampleInputs)
            XCTFail("Expected validationFailed error")
        } catch let error as VibeGeneratorError {
            switch error {
            case .validationFailed: break
            default: XCTFail("Expected validationFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected VibeGeneratorError.validationFailed, got \(error)")
        }
    }

    func testLongRejectsSourceTagRepeats() async {
        let badDescription = Self.descriptionReply(
            long: "Dark pressure hangs in a rainlit stairwell, metallic edges brushing warm concrete."
        )
        let mock = MockClient(replies: [badDescription, badDescription])
        let gen = VibeGeneratorV2(client: mock)
        do {
            _ = try await gen.generate(inputs: sampleInputs)
            XCTFail("Expected validationFailed error")
        } catch let error as VibeGeneratorError {
            switch error {
            case .validationFailed: break
            default: XCTFail("Expected validationFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected VibeGeneratorError.validationFailed, got \(error)")
        }
    }

    func testLongRejectsArticleLeadAndGenericTrackNoun() async {
        let badDescription = Self.descriptionReply(
            long: "A vibrant track glows with crowded heat and chrome sparks."
        )
        let mock = MockClient(replies: [badDescription, badDescription])
        let gen = VibeGeneratorV2(client: mock)
        do {
            _ = try await gen.generate(inputs: sampleInputs)
            XCTFail("Expected validationFailed error")
        } catch let error as VibeGeneratorError {
            switch error {
            case .validationFailed: break
            default: XCTFail("Expected validationFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected VibeGeneratorError.validationFailed, got \(error)")
        }
    }

    func testValidationFailureRetriesDescriptionWithRepairHint() async throws {
        let badDescription = Self.descriptionReply(weight: ["HOUSE"])
        let spy = SpyClient()
        spy.replies = [badDescription, Self.validDescriptionReply, Self.validMovementReply]
        let gen = VibeGeneratorV2(client: spy)

        let result = try await gen.generate(inputs: sampleInputs)

        XCTAssertEqual(result.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(result.mixHint, "2AM bridge after rough drums before melodic release")
        XCTAssertEqual(spy.maxTokens, [600, 600, 300])
        XCTAssertEqual(spy.prompts.count, 3)
        XCTAssertTrue(spy.prompts[1].contains("Previous response failed validation"))
        XCTAssertTrue(spy.prompts[1].contains("weight_options has no usable word candidates"))
    }

    func testParsingFailureRetriesDescriptionWithRepairHint() async throws {
        let spy = SpyClient()
        spy.replies = [
            "LOOKING AT THIS TRACK ANALYSIS: no JSON object here",
            Self.validDescriptionReply,
            Self.validMovementReply
        ]
        let gen = VibeGeneratorV2(client: spy)

        let result = try await gen.generate(inputs: sampleInputs)

        XCTAssertEqual(result.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(result.mixHint, "2AM bridge after rough drums before melodic release")
        XCTAssertEqual(spy.maxTokens, [600, 600, 300])
        XCTAssertEqual(spy.prompts.count, 3)
        XCTAssertTrue(spy.prompts[1].contains("Previous response failed validation"))
        XCTAssertTrue(spy.prompts[1].contains("Parsing failed"))
    }

    func testDescriptionCanRegenerateThroughMultipleValidationFailures() async throws {
        let tooLongDescription = Self.descriptionReply(
            long: "Undulating waves roll beneath ornate patterns, creating hypnotic chambers that pulse with ancient rhythms and modern electronics."
        )
        let spy = SpyClient()
        spy.replies = [
            tooLongDescription,
            tooLongDescription,
            Self.validDescriptionReply,
            Self.validMovementReply
        ]
        let gen = VibeGeneratorV2(client: spy)

        let result = try await gen.generate(inputs: sampleInputs)

        XCTAssertEqual(result.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(result.long, "Velvet pressure hangs in a rainlit stairwell, metallic edges brushing warm concrete.")
        XCTAssertEqual(result.mixHint, "2AM bridge after rough drums before melodic release")
        XCTAssertEqual(spy.maxTokens, [600, 600, 600, 300])
        XCTAssertTrue(spy.prompts[1].contains("long must be 10 to 16 words"))
        XCTAssertTrue(spy.prompts[2].contains("long must be 10 to 16 words"))
    }

    func testMovementRejectsCompletedDescriptionRepeats() async {
        let badMovement = #"{"mix_hint":"2AM bridge after velvet drums before melodic release"}"#
        let mock = MockClient(replies: [Self.validDescriptionReply, badMovement])
        let gen = VibeGeneratorV2(client: mock)
        do {
            _ = try await gen.generate(inputs: sampleInputs)
            XCTFail("Expected validationFailed error")
        } catch let error as VibeGeneratorError {
            switch error {
            case .validationFailed: break
            default: XCTFail("Expected validationFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected VibeGeneratorError.validationFailed, got \(error)")
        }
    }

    func testBatchLedgerPenalizesRepeatedSlotWords() async throws {
        let ledger = VibeBatchLedger()
        await ledger.record(
            VibeGenerationResult(
                short: "HEAVY RUBBERY URGENT ENGINE",
                long: "Copper stairs hum above moonlit rain and distant silver pressure.",
                mixHint: "2AM bridge after rough drums before melodic release"
            )
        )
        let reply = Self.descriptionReply(
            weight: ["HEAVY", "MASSIVE"],
            texture: ["RUBBERY", "GLASSY"],
            emotion: ["URGENT", "TENDER"],
            signature: ["ENGINE", "VEIL"],
            long: "Glass sparks drift over cotton rooftops and soft mirror rain."
        )
        let mock = MockClient(replies: [reply, Self.validMovementReply])
        let gen = VibeGeneratorV2(client: mock)

        let result = try await gen.generate(inputs: sampleInputs, batchLedger: ledger)

        XCTAssertEqual(result.short, "MASSIVE GLASSY TENDER VEIL")
    }

    func testBatchImageRepeatsRemainSoftPressure() async throws {
        let ledger = VibeBatchLedger()
        await ledger.record(
            VibeGenerationResult(
                short: "HEAVY RUBBERY URGENT ENGINE",
                long: "Velvet midnight waves fold under copper rain and distant stairs.",
                mixHint: "2AM bridge after rough drums before melodic release"
            )
        )
        let reply = Self.descriptionReply(
            weight: ["MASSIVE"],
            texture: ["CRISP"],
            emotion: ["TENDER"],
            signature: ["VEIL"],
            long: "Velvet midnight waves braid each silver doorway after warm rain."
        )
        let mock = MockClient(replies: [reply, Self.validMovementReply])
        let gen = VibeGeneratorV2(client: mock)

        let result = try await gen.generate(inputs: sampleInputs, batchLedger: ledger)

        XCTAssertEqual(result.short, "MASSIVE CRISP TENDER VEIL")
        XCTAssertEqual(result.long, "Velvet midnight waves braid each silver doorway after warm rain.")
    }

    func testLongFormulaWordsRemainSoftPressure() async throws {
        let reply = Self.descriptionReply(
            long: "Copper sparks keep creating a glass hallway after rain and velvet dusk."
        )
        let mock = MockClient(replies: [reply, Self.validMovementReply])
        let gen = VibeGeneratorV2(client: mock)

        let result = try await gen.generate(inputs: sampleInputs)

        XCTAssertEqual(result.short, "HEAVY RUBBERY URGENT ENGINE")
        XCTAssertEqual(result.long, "Copper sparks keep creating a glass hallway after rain and velvet dusk.")
    }

    func testTemperatureAndModelMatchSpec() async {
        let spy = SpyClient()
        let gen = VibeGeneratorV2(client: spy)
        _ = try? await gen.generate(inputs: sampleInputs)
        XCTAssertEqual(spy.temperatures, [0.7, 0.7])
        XCTAssertEqual(spy.models, [AnthropicClient.defaultModel, AnthropicClient.defaultModel])
        XCTAssertEqual(spy.maxTokens, [600, 300])
        XCTAssertEqual(spy.prompts.count, 2)
        XCTAssertTrue(spy.prompts[0].contains("Write slot candidate arrays and `long`"))
        XCTAssertTrue(spy.systems[0].contains("weight_options"))
        XCTAssertTrue(spy.systems[0].contains("Composer selector vocabulary"))
        XCTAssertTrue(spy.prompts[1].contains("Completed fields"))
    }
}
