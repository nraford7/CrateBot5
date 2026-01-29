import XCTest
@testable import CrateBotCore

final class TrainingConfigurationTests: XCTestCase {
    func testDefaultValues() {
        let config = TrainingConfiguration()

        XCTAssertEqual(config.minSamplesPerTag, 50)
        XCTAssertEqual(config.maxNegativeRatio, 3.0)
        XCTAssertEqual(config.mixupAlpha, 0.4)
        XCTAssertEqual(config.mixupRatio, 0.3)
        XCTAssertEqual(config.featureNoisePercent, 0.02)
        XCTAssertEqual(config.validationSplit, 0.2)
        XCTAssertTrue(config.enableMixup)
        XCTAssertTrue(config.enableFeatureNoise)
        XCTAssertEqual(config.treeMaxDepth, 6)
        XCTAssertEqual(config.treeIterations, 100)
        XCTAssertEqual(config.treeStepSize, 0.3)
        XCTAssertTrue(config.enableLabelSmoothing)
        XCTAssertEqual(config.labelSmoothingFactor, 0.1)
        XCTAssertTrue(config.enableContrastiveLoss)
        XCTAssertEqual(config.randomSeed, 42)
    }

    func testCustomConfiguration() {
        let config = TrainingConfiguration(
            minSamplesPerTag: 100,
            maxNegativeRatio: 5.0,
            enableMixup: false
        )

        XCTAssertEqual(config.minSamplesPerTag, 100)
        XCTAssertEqual(config.maxNegativeRatio, 5.0)
        XCTAssertFalse(config.enableMixup)
        // Other values should still be defaults
        XCTAssertEqual(config.mixupAlpha, 0.4)
    }

    func testCodable() throws {
        let original = TrainingConfiguration(
            minSamplesPerTag: 75,
            maxNegativeRatio: 4.0,
            enableMixup: false,
            treeMaxDepth: 8
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrainingConfiguration.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testEquatable() {
        let config1 = TrainingConfiguration()
        let config2 = TrainingConfiguration()
        let config3 = TrainingConfiguration(minSamplesPerTag: 100)

        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }

    func testStaticDefault() {
        let defaultConfig = TrainingConfiguration.default
        let newConfig = TrainingConfiguration()

        XCTAssertEqual(defaultConfig, newConfig)
    }
}
