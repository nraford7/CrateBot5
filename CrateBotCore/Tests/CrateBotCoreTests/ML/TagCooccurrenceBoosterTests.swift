import XCTest
@testable import CrateBotCore

final class TagCooccurrenceBoosterTests: XCTestCase {

    // Synthetic stats for testing: 100 tracks, House is 50%, Driving is 40%,
    // P(Driving | House) = 0.9 (strong positive lift), P(Techno | House) = 0.05 (negative)
    private func makeBooster() -> TagCooccurrenceBooster {
        let stats = TagCooccurrenceBooster.Stats(
            totalTracks: 100,
            baseRates: ["House": 0.5, "Driving": 0.4, "Techno": 0.1, "Happy": 0.3, "Aggressive": 0.2],
            conditional: [
                "House": ["Driving": 0.9, "Techno": 0.05],
                "Aggressive": ["Happy": 0.02]
            ]
        )
        return TagCooccurrenceBooster(stats: stats, boostWeight: 0.5, confidentThreshold: 0.8)
    }

    func testNoConfidentTagsNoChange() {
        let booster = makeBooster()
        // All raw probabilities below threshold — no boosting
        let raw: [String: Float] = ["House": 0.5, "Driving": 0.4, "Techno": 0.1]
        let adjusted = booster.adjust(probabilities: raw)
        for (tag, p) in raw {
            XCTAssertEqual(adjusted[tag] ?? 0, p, accuracy: 0.001, "Tag \(tag) should be unchanged")
        }
    }

    func testConfidentTagBoostsCorrelatedTag() {
        let booster = makeBooster()
        // House is highly confident — Driving should be boosted (lift = 0.9/0.4 = 2.25)
        let raw: [String: Float] = ["House": 0.95, "Driving": 0.5, "Techno": 0.2]
        let adjusted = booster.adjust(probabilities: raw)
        XCTAssertGreaterThan(adjusted["Driving"] ?? 0, 0.5, "Driving should be boosted")
        XCTAssertLessThan(adjusted["Techno"] ?? 1, 0.2, "Techno should be penalized (negative lift)")
    }

    func testConfidentTagIsNotSelfBoosted() {
        let booster = makeBooster()
        let raw: [String: Float] = ["House": 0.95, "Driving": 0.5]
        let adjusted = booster.adjust(probabilities: raw)
        // House itself should not be modified based on its own confidence
        XCTAssertEqual(adjusted["House"] ?? 0, 0.95, accuracy: 0.01)
    }

    func testMutuallyExclusiveTagsPenalize() {
        let booster = makeBooster()
        // Aggressive is confident, Happy has a strong negative lift (0.02 / 0.3 = 0.067)
        let raw: [String: Float] = ["Aggressive": 0.9, "Happy": 0.6]
        let adjusted = booster.adjust(probabilities: raw)
        XCTAssertLessThan(adjusted["Happy"] ?? 1, 0.6, "Happy should be penalized")
    }

    func testAdjustmentIsClampedToValidRange() {
        let booster = makeBooster()
        let raw: [String: Float] = ["House": 0.99, "Driving": 0.99]
        let adjusted = booster.adjust(probabilities: raw)
        for (_, p) in adjusted {
            XCTAssertGreaterThanOrEqual(p, 0.0)
            XCTAssertLessThanOrEqual(p, 1.0)
        }
    }

    func testMissingStatsForTagLeavesUnchanged() {
        let booster = makeBooster()
        // "Mystery" is not in stats — should pass through unchanged
        let raw: [String: Float] = ["House": 0.95, "Mystery": 0.6]
        let adjusted = booster.adjust(probabilities: raw)
        XCTAssertEqual(adjusted["Mystery"] ?? 0, 0.6, accuracy: 0.001)
    }

    func testLoadFromBundleSucceeds() {
        let booster = TagCooccurrenceBooster.loadFromBundle()
        XCTAssertNotNil(booster, "Booster should load from bundled resource")
    }
}
