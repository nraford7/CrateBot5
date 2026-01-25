import Foundation
import Accelerate

/// Audio augmentation utilities for training robustness
public struct AudioAugmenter: Sendable {

    public struct AugmentationConfig: Sendable {
        public let specAugmentEnabled: Bool
        public let mixupEnabled: Bool
        public let mixupAlpha: Float
        public let freqMaskCount: Int
        public let freqMaskWidth: Int
        public let timeMaskCount: Int
        public let timeMaskWidth: Int

        public static let `default` = AugmentationConfig(
            specAugmentEnabled: true,
            mixupEnabled: true,
            mixupAlpha: 0.4,
            freqMaskCount: 2,
            freqMaskWidth: 15,
            timeMaskCount: 2,
            timeMaskWidth: 25
        )

        public static let none = AugmentationConfig(
            specAugmentEnabled: false,
            mixupEnabled: false,
            mixupAlpha: 0,
            freqMaskCount: 0,
            freqMaskWidth: 0,
            timeMaskCount: 0,
            timeMaskWidth: 0
        )

        public init(
            specAugmentEnabled: Bool = true,
            mixupEnabled: Bool = true,
            mixupAlpha: Float = 0.4,
            freqMaskCount: Int = 2,
            freqMaskWidth: Int = 15,
            timeMaskCount: Int = 2,
            timeMaskWidth: Int = 25
        ) {
            self.specAugmentEnabled = specAugmentEnabled
            self.mixupEnabled = mixupEnabled
            self.mixupAlpha = mixupAlpha
            self.freqMaskCount = freqMaskCount
            self.freqMaskWidth = freqMaskWidth
            self.timeMaskCount = timeMaskCount
            self.timeMaskWidth = timeMaskWidth
        }
    }

    // MARK: - SpecAugment

    /// Apply SpecAugment to a mel spectrogram
    public static func applySpecAugment(
        to spectrogram: [[Float]],
        config: AugmentationConfig = .default
    ) -> [[Float]] {
        guard config.specAugmentEnabled else { return spectrogram }
        guard !spectrogram.isEmpty, !spectrogram[0].isEmpty else { return spectrogram }

        var augmented = spectrogram
        let freqBins = spectrogram.count
        let timeSteps = spectrogram[0].count

        // Frequency masking
        for _ in 0..<config.freqMaskCount {
            let width = Int.random(in: 1...config.freqMaskWidth)
            let start = Int.random(in: 0..<max(1, freqBins - width))
            for f in start..<min(start + width, freqBins) {
                augmented[f] = [Float](repeating: 0, count: timeSteps)
            }
        }

        // Time masking
        for _ in 0..<config.timeMaskCount {
            let width = Int.random(in: 1...config.timeMaskWidth)
            let start = Int.random(in: 0..<max(1, timeSteps - width))
            for f in 0..<freqBins {
                for t in start..<min(start + width, timeSteps) {
                    augmented[f][t] = 0
                }
            }
        }

        return augmented
    }

    // MARK: - Mixup

    public struct MixupResult: Sendable {
        public let features: [Float]
        public let softLabels: [String: Float]  // class -> weight
    }

    /// Apply Mixup between two samples
    public static func mixup(
        features1: [Float],
        features2: [Float],
        label1: String,
        label2: String,
        alpha: Float = 0.4
    ) -> MixupResult {
        // Handle empty arrays gracefully
        let minCount = min(features1.count, features2.count)
        guard minCount > 0 else {
            // Return empty features with 50/50 soft labels
            var softLabels: [String: Float] = [:]
            if label1 == label2 {
                softLabels[label1] = 1.0
            } else {
                softLabels[label1] = 0.5
                softLabels[label2] = 0.5
            }
            return MixupResult(features: [], softLabels: softLabels)
        }

        // Sample lambda from Beta distribution (approximated)
        let lambda = sampleBeta(alpha: alpha, beta: alpha)

        // Mix features: lambda * features1 + (1-lambda) * features2
        // Use min length to handle mismatched dimensions
        var mixedFeatures = [Float](repeating: 0, count: minCount)
        for i in 0..<minCount {
            mixedFeatures[i] = lambda * features1[i] + (1 - lambda) * features2[i]
        }

        // Soft labels
        var softLabels: [String: Float] = [:]
        if label1 == label2 {
            softLabels[label1] = 1.0
        } else {
            softLabels[label1] = lambda
            softLabels[label2] = 1.0 - lambda
        }

        return MixupResult(features: mixedFeatures, softLabels: softLabels)
    }

    /// Approximate Beta distribution sampling
    private static func sampleBeta(alpha: Float, beta: Float) -> Float {
        if alpha <= 1.0 {
            return Float.random(in: 0.3...0.7)
        }
        let u1 = Float.random(in: 0.0001...0.9999)
        let u2 = Float.random(in: 0.0001...0.9999)
        let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        let mean: Float = 0.5
        let std: Float = 0.15
        return max(0.1, min(0.9, mean + std * z))
    }

    // MARK: - Feature Augmentation

    /// Apply augmentation directly to embedding features
    public static func augmentFeatures(
        _ features: [Float],
        addNoise: Bool = true,
        noiseScale: Float = 0.01
    ) -> [Float] {
        guard addNoise else { return features }
        return features.map { value in
            let noise = Float.random(in: -noiseScale...noiseScale)
            return value + noise
        }
    }
}
