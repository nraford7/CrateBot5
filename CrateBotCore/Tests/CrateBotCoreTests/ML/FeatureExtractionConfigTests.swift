import XCTest
@testable import CrateBotCore

final class FeatureExtractionConfigTests: XCTestCase {

    func testConfigHashIncludesAllParameters() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        // Same config should produce same hash
        XCTAssertEqual(config1.configHash, config2.configHash)
        XCTAssertFalse(config1.configHash.isEmpty)
    }

    func testConfigHashChangesWhenSegmentDurationChanges() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 20.0,  // Different duration
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testConfigHashChangesWhenFeatureConfigChanges() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetPlusGenres,  // Different feature config
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testConfigHashChangesWhenSegmentFractionsChange() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.25, 0.5, 0.75]  // Different fractions
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testDefaultConfig() {
        let config = FeatureExtractionConfig.default

        XCTAssertEqual(config.featureConfig, .effnetGenresCLAPMAEST)
        XCTAssertEqual(config.segmentDuration, 30.0)
        XCTAssertEqual(config.segmentStartFractions, [0.33, 0.5, 0.66])
    }

    func testDefaultConfigHasFiveWindows() {
        let config = FeatureExtractionConfig.default
        XCTAssertEqual(config.windowFractions, [0.1, 0.3, 0.5, 0.7, 0.9])
        XCTAssertEqual(config.clapWindowFractions, [0.25, 0.5, 0.75])
        XCTAssertEqual(config.windowDuration, 15.0)
    }

    func testWindowFieldsChangeConfigHash() {
        let a = FeatureExtractionConfig.default
        let b = FeatureExtractionConfig(
            featureConfig: a.featureConfig,
            segmentDuration: a.segmentDuration,
            segmentStartFractions: a.segmentStartFractions,
            windowDuration: 15.0,
            windowFractions: [0.5],          // different windows
            clapWindowFractions: [0.5]
        )
        XCTAssertNotEqual(a.configHash, b.configHash)
    }
}
