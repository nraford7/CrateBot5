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

    func testMissingBPMUsesSentinel() {
        let v = JudgmentFeatureVector(binaryConfidences: [:], groupProbabilities: [:],
                                      bpm: nil, durationSeconds: 200)
        XCTAssertEqual(v.values[v.columnNames.firstIndex(of: "bpm")!], -1.0)
    }
}
