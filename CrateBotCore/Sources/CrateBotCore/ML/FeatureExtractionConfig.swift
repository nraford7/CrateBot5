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

    /// Duration of each analysis window in seconds (EffNet/MAEST read the head of each window)
    public let windowDuration: Double

    /// Window start positions as fractions of track length (EffNet + Genres + MAEST)
    public let windowFractions: [Double]

    /// Window start positions for CLAP (10s input, fewer windows)
    public let clapWindowFractions: [Double]

    public init(
        featureConfig: CombinedFeatureExtractor.FeatureConfig,
        segmentDuration: Double,
        segmentStartFractions: [Double],
        windowDuration: Double = 15.0,
        windowFractions: [Double] = [0.1, 0.3, 0.5, 0.7, 0.9],
        clapWindowFractions: [Double] = [0.25, 0.5, 0.75]
    ) {
        self.featureConfig = featureConfig
        self.segmentDuration = segmentDuration
        self.segmentStartFractions = segmentStartFractions
        self.windowDuration = windowDuration
        self.windowFractions = windowFractions
        self.clapWindowFractions = clapWindowFractions
    }

    /// Default configuration matching current TrainingDataCollector defaults
    public static let `default` = FeatureExtractionConfig(
        featureConfig: .effnetGenresCLAPMAEST,
        segmentDuration: 30.0,
        segmentStartFractions: [0.33, 0.5, 0.66],
        windowDuration: 15.0,
        windowFractions: [0.1, 0.3, 0.5, 0.7, 0.9],
        clapWindowFractions: [0.25, 0.5, 0.75]
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
