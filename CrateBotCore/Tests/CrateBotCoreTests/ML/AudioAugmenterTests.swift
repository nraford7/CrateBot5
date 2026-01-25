import XCTest
@testable import CrateBotCore

final class AudioAugmenterTests: XCTestCase {

    func testSpecAugmentMasksFrequencies() {
        let spectrogram = [[Float]](repeating: [Float](repeating: 1.0, count: 100), count: 64)
        let config = AudioAugmenter.AugmentationConfig(
            specAugmentEnabled: true,
            mixupEnabled: false,
            freqMaskCount: 2,
            freqMaskWidth: 10,
            timeMaskCount: 0,
            timeMaskWidth: 0
        )

        let augmented = AudioAugmenter.applySpecAugment(to: spectrogram, config: config)
        let zeroRows = augmented.filter { row in row.allSatisfy { $0 == 0 } }.count
        XCTAssertGreaterThan(zeroRows, 0)
    }

    func testMixupBlendsFeaturesAndLabels() {
        let features1 = [Float](repeating: 1.0, count: 1680)
        let features2 = [Float](repeating: 0.0, count: 1680)

        let result = AudioAugmenter.mixup(
            features1: features1,
            features2: features2,
            label1: "ClassA",
            label2: "ClassB",
            alpha: 0.4
        )

        XCTAssertTrue(result.features.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(result.softLabels.count, 2)
        XCTAssertEqual(result.softLabels.values.reduce(0, +), 1.0, accuracy: 0.01)
    }

    func testMixupWithMismatchedDimensions() {
        let features1 = [Float](repeating: 1.0, count: 100)
        let features2 = [Float](repeating: 0.0, count: 50)  // Shorter

        let result = AudioAugmenter.mixup(
            features1: features1,
            features2: features2,
            label1: "A",
            label2: "B",
            alpha: 0.4
        )

        // Should use the shorter length, not crash
        XCTAssertEqual(result.features.count, 50)
        XCTAssertTrue(result.features.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testMixupWithEmptyFeatures() {
        let features1 = [Float](repeating: 1.0, count: 100)
        let features2: [Float] = []

        let result = AudioAugmenter.mixup(
            features1: features1,
            features2: features2,
            label1: "A",
            label2: "B",
            alpha: 0.4
        )

        // Empty input should produce empty output
        XCTAssertEqual(result.features.count, 0)
    }
}
