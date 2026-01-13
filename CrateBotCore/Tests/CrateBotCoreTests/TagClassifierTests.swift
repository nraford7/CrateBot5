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
}
