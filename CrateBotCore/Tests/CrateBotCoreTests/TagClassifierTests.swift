import XCTest
@testable import CrateBotCore

final class TagClassifierTests: XCTestCase {
    func testTagClassifierErrorDescriptions() {
        let invalidOutput = TagClassifierError.invalidOutput
        XCTAssertNotNil(invalidOutput.errorDescription)

        let dimensionMismatch = TagClassifierError.featureDimensionMismatch(expected: 512, got: 256)
        XCTAssertTrue(dimensionMismatch.errorDescription?.contains("512") ?? false)
    }

    func testMultiLabelPredictorEmptyClassifiers() async throws {
        let predictor = MultiLabelPredictor(classifiers: [])
        let features = [Float](repeating: 0.5, count: 32)

        let tags = try await predictor.predict(features: features)
        XCTAssertEqual(tags, [])
    }

    func testTagClassifierMultiArrayShapeDetection() {
        // Test that feature count is correctly extracted from various multiarray shapes
        // Shape [1, 1680] should give featureCount = 1680, not 1
        // Shape [1680] should give featureCount = 1680

        // Shape [1, 1680] - batch dimension first
        let shape1 = [NSNumber(value: 1), NSNumber(value: 1680)]
        let featureCount1 = TagClassifier.extractFeatureCount(from: shape1)
        XCTAssertEqual(featureCount1, 1680, "Shape [1, 1680] should extract 1680 features")

        // Shape [1680] - no batch dimension
        let shape2 = [NSNumber(value: 1680)]
        let featureCount2 = TagClassifier.extractFeatureCount(from: shape2)
        XCTAssertEqual(featureCount2, 1680, "Shape [1680] should extract 1680 features")

        // Shape [1, 1, 1680] - multiple leading 1s
        let shape3 = [NSNumber(value: 1), NSNumber(value: 1), NSNumber(value: 1680)]
        let featureCount3 = TagClassifier.extractFeatureCount(from: shape3)
        XCTAssertEqual(featureCount3, 1680, "Shape [1, 1, 1680] should extract 1680 features")
    }
}
