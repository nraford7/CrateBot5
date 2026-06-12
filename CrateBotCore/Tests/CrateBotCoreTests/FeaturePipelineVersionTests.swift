import XCTest
@testable import CrateBotCore

final class FeaturePipelineVersionTests: XCTestCase {
    func testVersionHashIsConsistent() {
        let version1 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1", "apple": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        let version2 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1", "apple": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        XCTAssertEqual(version1.versionHash, version2.versionHash)
    }

    func testVersionHashChangeOnExtractorUpdate() {
        let version1 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        let version2 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v2"],  // Changed
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        XCTAssertNotEqual(version1.versionHash, version2.versionHash)
    }

    func testCurrentEncodesConfigWindowFractions() {
        // Default-config hash is stable across calls
        XCTAssertEqual(
            FeaturePipelineVersion.current().versionHash,
            FeaturePipelineVersion.current(for: .default).versionHash
        )

        // A config with different window fractions yields a different hash
        let altConfig = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAPMAEST,
            windowDuration: 15.0,
            windowFractions: [0.2, 0.5, 0.8],
            clapWindowFractions: [0.25, 0.5, 0.75]
        )
        XCTAssertNotEqual(
            FeaturePipelineVersion.current().versionHash,
            FeaturePipelineVersion.current(for: altConfig).versionHash
        )
    }

    func testVersionHashChangeOnNormalizationChange() {
        let version1 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        let version2 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "minmax", perFeature: true, clipMin: 0, clipMax: 1)  // Changed
        )

        XCTAssertNotEqual(version1.versionHash, version2.versionHash)
    }
}
