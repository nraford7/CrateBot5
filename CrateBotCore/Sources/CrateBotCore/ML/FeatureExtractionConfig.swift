import Foundation
import CryptoKit

/// Configuration for feature extraction that affects cache compatibility.
/// Changes to any of these parameters require cache invalidation.
public struct FeatureExtractionConfig: Codable, Equatable, Sendable {
    /// Which feature extractors to use (EffNet only, +Genres, or +CLAP)
    public let featureConfig: CombinedFeatureExtractor.FeatureConfig

    /// Duration of each audio segment in seconds
    public let segmentDuration: Double

    /// Start positions as fractions of total track duration
    public let segmentStartFractions: [Double]

    public init(
        featureConfig: CombinedFeatureExtractor.FeatureConfig,
        segmentDuration: Double,
        segmentStartFractions: [Double]
    ) {
        self.featureConfig = featureConfig
        self.segmentDuration = segmentDuration
        self.segmentStartFractions = segmentStartFractions
    }

    /// Default configuration matching current TrainingDataCollector defaults
    public static let `default` = FeatureExtractionConfig(
        featureConfig: .effnetGenresCLAP,
        segmentDuration: 30.0,
        segmentStartFractions: [0.33, 0.5, 0.66]
    )

    /// Deterministic hash for cache key comparison
    public var configHash: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        guard let data = try? encoder.encode(self) else {
            return "invalid"
        }

        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
