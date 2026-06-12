import XCTest
@testable import CrateBotCore

/// Mock Stage 1 predictor — deterministic outputs derived from the input
/// features so tests can assert exact column values without CoreML.
private struct MockStage1Predictor: Stage1Predictor {
    func confidences(
        features: [Float]
    ) async throws -> (binary: [String: Float], groups: [String: [String: Float]]) {
        let seed = features.first ?? 0
        return (
            binary: ["Dark": seed, "Aggressive": seed / 2],
            groups: ["BassType": ["Punchy": seed / 4, "Walking": 1 - seed / 4]]
        )
    }
}

/// Mock predictor that fails on every call — proves the generator never
/// invokes Stage 1 for tracks that produce no training row.
private struct ExplodingPredictor: Stage1Predictor {
    struct ShouldNotBeCalled: Error {}
    func confidences(
        features: [Float]
    ) async throws -> (binary: [String: Float], groups: [String: [String: Float]]) {
        throw ShouldNotBeCalled()
    }
}

final class JudgmentDataGeneratorTests: XCTestCase {

    private func makeGenerator(
        predictor: any Stage1Predictor = MockStage1Predictor(),
        bpm: @escaping @Sendable (String) async -> Float? = { _ in 128 },
        duration: @escaping @Sendable (String) async -> Float? = { _ in 372 }
    ) -> JudgmentDataGenerator {
        JudgmentDataGenerator(
            predictor: predictor,
            bpmLookup: bpm,
            durationLookup: duration
        )
    }

    // MARK: - Row construction

    func testBuildsRowFromPredictorOutputsAndLookups() async throws {
        let track = TaggedTrack(
            id: "/music/a.mp3",
            tags: ["Peak", "House"],
            features: [0.8, 0.1],
            tagsByCategory: ["Timing": ["Peak"], "Genre": ["House"]]
        )

        let (rows, skipped) = try await makeGenerator().generate(from: [track])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(skipped, 0)

        let row = rows[0]
        XCTAssertEqual(row.trackID, "/music/a.mp3")
        XCTAssertEqual(row.labels, ["Peak"])
        XCTAssertEqual(row.features.columnNames,
            ["bin_Aggressive", "bin_Dark", "grp_BassType_Punchy", "grp_BassType_Walking",
             "bpm", "duration"])
        XCTAssertEqual(row.features.values, [0.4, 0.8, 0.2, 0.8, 128, 372])
    }

    func testLabelsAreTimingTagsOnly() async throws {
        let track = TaggedTrack(
            id: "/music/b.mp3",
            tags: ["Build", "Dark", "Techno"],
            features: [0.5],
            tagsByCategory: ["Timing": ["Build"], "Mood": ["Dark"], "Genre": ["Techno"]]
        )

        let (rows, _) = try await makeGenerator().generate(from: [track])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].labels, ["Build"])
    }

    func testMissingBPMAndDurationUseSentinel() async throws {
        let track = TaggedTrack(
            id: "/music/c.mp3",
            tags: ["Peak"],
            features: [0.5],
            tagsByCategory: ["Timing": ["Peak"]]
        )
        let generator = makeGenerator(bpm: { _ in nil }, duration: { _ in nil })

        let (rows, _) = try await generator.generate(from: [track])

        let row = try XCTUnwrap(rows.first)
        let bpmIndex = try XCTUnwrap(row.features.columnNames.firstIndex(of: "bpm"))
        let durationIndex = try XCTUnwrap(row.features.columnNames.firstIndex(of: "duration"))
        XCTAssertEqual(row.features.values[bpmIndex], -1.0)
        XCTAssertEqual(row.features.values[durationIndex], -1.0)
    }

    // MARK: - Category-complete target filtering

    func testTrackWithoutTimingTagsProducesNoRow() async throws {
        // Unknown, not negative: a track never assessed for Timing must not
        // become a Stage 2 training row. The predictor would throw if called.
        let untagged = TaggedTrack(
            id: "/music/d.mp3",
            tags: ["House"],
            features: [0.5],
            tagsByCategory: ["Genre": ["House"]]
        )
        let generator = makeGenerator(predictor: ExplodingPredictor())

        let (rows, skipped) = try await generator.generate(from: [untagged])

        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(skipped, 0)  // excluded by design, not "skipped"
    }

    func testCategoryKeysMatchCaseInsensitively() async throws {
        // Mirrors BinaryTrainingDataGenerator: "timing" and "Timing" behave identically.
        let track = TaggedTrack(
            id: "/music/e.mp3",
            tags: ["Peak"],
            features: [0.5],
            tagsByCategory: ["timing": ["Peak"]]
        )

        let (rows, _) = try await makeGenerator().generate(from: [track])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].labels, ["Peak"])
    }

    // MARK: - Skipped counting

    func testTracksWithoutCachedFeaturesAreSkippedAndCounted() async throws {
        let noFeatures = TaggedTrack(
            id: "/music/f.mp3",
            tags: ["Peak"],
            features: nil,
            tagsByCategory: ["Timing": ["Peak"]]
        )
        let emptyFeatures = TaggedTrack(
            id: "/music/g.mp3",
            tags: ["Build"],
            features: [],
            tagsByCategory: ["Timing": ["Build"]]
        )
        let good = TaggedTrack(
            id: "/music/h.mp3",
            tags: ["Sustain"],
            features: [0.5],
            tagsByCategory: ["Timing": ["Sustain"]]
        )

        let (rows, skipped) = try await makeGenerator().generate(
            from: [noFeatures, emptyFeatures, good])

        XCTAssertEqual(skipped, 2)
        XCTAssertEqual(rows.map(\.trackID), ["/music/h.mp3"])
    }
}
