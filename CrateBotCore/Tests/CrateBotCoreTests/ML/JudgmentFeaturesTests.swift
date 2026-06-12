import XCTest
@testable import CrateBotCore

final class JudgmentFeaturesTests: XCTestCase {

    func testColumnOrderIsDeterministicAndSorted() {
        let v = JudgmentFeatureVector(
            binaryConfidences: ["Dark": 0.8, "Aggressive": 0.5],
            groupProbabilities: ["BassType": ["Punchy": 0.7, "Walking": 0.3]],
            bpm: 128, durationSeconds: 372)
        XCTAssertEqual(v.columnNames,
            ["bin_Aggressive", "bin_Dark", "grp_BassType_Punchy", "grp_BassType_Walking",
             "bpm", "duration"])
        XCTAssertEqual(v.values, [0.5, 0.8, 0.7, 0.3, 128, 372])
    }

    /// Missing-value semantics live INSIDE the schema type: nil bpm AND nil
    /// duration both become the shared sentinel here, not at call sites.
    func testMissingBPMAndDurationUseSharedSentinel() {
        let v = JudgmentFeatureVector(binaryConfidences: [:], groupProbabilities: [:],
                                      bpm: nil, durationSeconds: nil)
        XCTAssertEqual(v.values[v.columnNames.firstIndex(of: "bpm")!],
                       JudgmentFeatureVector.missingValueSentinel)
        XCTAssertEqual(v.values[v.columnNames.firstIndex(of: "duration")!],
                       JudgmentFeatureVector.missingValueSentinel)
        XCTAssertEqual(JudgmentFeatureVector.missingValueSentinel, -1.0)
    }
}
