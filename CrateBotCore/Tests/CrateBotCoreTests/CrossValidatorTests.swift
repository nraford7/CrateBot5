import XCTest
@testable import CrateBotCore

final class CrossValidatorTests: XCTestCase {

    func testKFoldSplitCreatesCorrectNumberOfFolds() {
        let tracks = (0..<100).map { TaggedTrack(id: "\($0)", tags: ["Tag"], features: [Float($0)]) }
        let validator = CrossValidator(folds: 5, seed: 42)

        let folds = validator.createFolds(from: tracks)

        XCTAssertEqual(folds.count, 5)
    }

    func testEachFoldHasUniqueTestSet() {
        let tracks = (0..<100).map { TaggedTrack(id: "\($0)", tags: ["Tag"], features: [Float($0)]) }
        let validator = CrossValidator(folds: 5, seed: 42)

        let folds = validator.createFolds(from: tracks)

        // Each fold's test set should be disjoint
        var allTestIds: Set<String> = []
        for fold in folds {
            let testIds = Set(fold.test.map(\.id))
            XCTAssertTrue(allTestIds.isDisjoint(with: testIds), "Test sets overlap")
            allTestIds.formUnion(testIds)
        }

        // All tracks should appear in exactly one test set
        XCTAssertEqual(allTestIds.count, tracks.count)
    }

    func testFoldSizesAreBalanced() {
        let tracks = (0..<100).map { TaggedTrack(id: "\($0)", tags: ["Tag"], features: [Float($0)]) }
        let validator = CrossValidator(folds: 5, seed: 42)

        let folds = validator.createFolds(from: tracks)

        // Each fold should have ~20 test samples
        for fold in folds {
            XCTAssertTrue((18...22).contains(fold.test.count), "Fold test size \(fold.test.count) not balanced")
            XCTAssertTrue((78...82).contains(fold.train.count), "Fold train size \(fold.train.count) not balanced")
        }
    }

    func testValidationMetricsCalculation() {
        // True positives: 8, False positives: 2, False negatives: 2, True negatives: 8
        let predictions: [(predicted: Bool, actual: Bool)] = [
            (true, true), (true, true), (true, true), (true, true),  // TP
            (true, true), (true, true), (true, true), (true, true),  // TP
            (true, false), (true, false),                            // FP
            (false, true), (false, true),                            // FN
            (false, false), (false, false), (false, false), (false, false),  // TN
            (false, false), (false, false), (false, false), (false, false),  // TN
        ]

        let metrics = ValidationMetrics.calculate(from: predictions)

        XCTAssertEqual(metrics.accuracy, 0.8, accuracy: 0.01)      // (8+8)/20 = 0.8
        XCTAssertEqual(metrics.precision, 0.8, accuracy: 0.01)     // 8/(8+2) = 0.8
        XCTAssertEqual(metrics.recall, 0.8, accuracy: 0.01)        // 8/(8+2) = 0.8
        XCTAssertEqual(metrics.f1Score, 0.8, accuracy: 0.01)       // 2*0.8*0.8/(0.8+0.8) = 0.8
    }

    func testPerfectPredictions() {
        let predictions: [(predicted: Bool, actual: Bool)] = [
            (true, true), (true, true), (false, false), (false, false)
        ]

        let metrics = ValidationMetrics.calculate(from: predictions)

        XCTAssertEqual(metrics.accuracy, 1.0)
        XCTAssertEqual(metrics.precision, 1.0)
        XCTAssertEqual(metrics.recall, 1.0)
        XCTAssertEqual(metrics.f1Score, 1.0)
    }

    func testAllNegativePredictions() {
        let predictions: [(predicted: Bool, actual: Bool)] = [
            (false, true), (false, true), (false, false), (false, false)
        ]

        let metrics = ValidationMetrics.calculate(from: predictions)

        XCTAssertEqual(metrics.accuracy, 0.5)
        XCTAssertEqual(metrics.precision, 0.0)  // No positive predictions
        XCTAssertEqual(metrics.recall, 0.0)     // No true positives
    }
}
