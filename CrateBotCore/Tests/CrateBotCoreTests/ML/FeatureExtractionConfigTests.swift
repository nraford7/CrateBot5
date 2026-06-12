import XCTest
@testable import CrateBotCore

final class FeatureExtractionConfigTests: XCTestCase {

    func testConfigHashIncludesAllParameters() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            windowDuration: 15.0,
            windowFractions: [0.1, 0.3, 0.5, 0.7, 0.9]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            windowDuration: 15.0,
            windowFractions: [0.1, 0.3, 0.5, 0.7, 0.9]
        )

        // Same config should produce same hash
        XCTAssertEqual(config1.configHash, config2.configHash)
        XCTAssertFalse(config1.configHash.isEmpty)
    }

    func testConfigHashChangesWhenWindowDurationChanges() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            windowDuration: 15.0
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            windowDuration: 10.0  // Different duration
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testConfigHashChangesWhenFeatureConfigChanges() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetPlusGenres  // Different feature config
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testConfigHashChangesWhenWindowFractionsChange() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            windowFractions: [0.1, 0.3, 0.5, 0.7, 0.9]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            windowFractions: [0.25, 0.5, 0.75]  // Different fractions
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testConfigHashChangesWhenCLAPWindowFractionsChange() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            clapWindowFractions: [0.25, 0.5, 0.75]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            clapWindowFractions: [0.5]  // Different fractions
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testDefaultConfig() {
        let config = FeatureExtractionConfig.default

        XCTAssertEqual(config.featureConfig, .effnetGenresCLAPMAEST)
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
            windowDuration: 15.0,
            windowFractions: [0.5],          // different windows
            clapWindowFractions: [0.5]
        )
        XCTAssertNotEqual(a.configHash, b.configHash)
    }
}
