import Foundation
import CryptoKit

public struct FeaturePipelineVersion: Codable, Equatable, Sendable {
    public let extractorVersions: [String: String]
    public let windowingParams: WindowingParams
    public let normalizationParams: NormalizationParams

    public struct WindowingParams: Codable, Equatable, Sendable {
        public let windowSize: Int
        public let hopSize: Int
        public let fftSize: Int

        public init(windowSize: Int, hopSize: Int, fftSize: Int) {
            self.windowSize = windowSize
            self.hopSize = hopSize
            self.fftSize = fftSize
        }
    }

    public struct NormalizationParams: Codable, Equatable, Sendable {
        public let method: String
        public let perFeature: Bool
        public let clipMin: Float?
        public let clipMax: Float?

        public init(method: String, perFeature: Bool, clipMin: Float? = nil, clipMax: Float? = nil) {
            self.method = method
            self.perFeature = perFeature
            self.clipMin = clipMin
            self.clipMax = clipMax
        }
    }

    public init(
        extractorVersions: [String: String],
        windowingParams: WindowingParams,
        normalizationParams: NormalizationParams
    ) {
        self.extractorVersions = extractorVersions
        self.windowingParams = windowingParams
        self.normalizationParams = normalizationParams
    }

    /// The pre-windowing (single-window) feature pipeline. Models stamped with
    /// this versionHash were trained on single-shot embeddings and are
    /// incompatible with multi-window mean-pooled features. Kept so loaders can
    /// detect and reject them explicitly.
    public static let legacySingleWindow = FeaturePipelineVersion(
        extractorVersions: ["effnet": "v1", "clap": "v1"],
        windowingParams: WindowingParams(
            windowSize: 512,    // 32ms at 16kHz (MusiCNN/EffNet)
            hopSize: 256,       // 16ms at 16kHz (MusiCNN/EffNet)
            fftSize: 512        // EffNet FFT size
        ),
        normalizationParams: NormalizationParams(
            method: "log_mel",
            perFeature: false
        )
    )

    /// The current feature pipeline: multi-window extraction with mean pooling.
    /// Encodes the given config's window fractions so any change to the
    /// windowing scheme changes the versionHash.
    public static func current(for config: FeatureExtractionConfig = .default) -> FeaturePipelineVersion {
        let windows = config.windowFractions.map { String($0) }.joined(separator: ",")
        let clapWindows = config.clapWindowFractions.map { String($0) }.joined(separator: ",")
        var extractors = legacySingleWindow.extractorVersions
        extractors["multiwindow"] = "d\(config.windowDuration)|w[\(windows)]|c[\(clapWindows)]"
        return FeaturePipelineVersion(
            extractorVersions: extractors,
            windowingParams: legacySingleWindow.windowingParams,
            normalizationParams: legacySingleWindow.normalizationParams
        )
    }

    /// Deterministic hash for cache key comparison
    public var versionHash: String {
        // Sort keys for deterministic encoding
        let sortedExtractors = extractorVersions.sorted { $0.key < $1.key }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        struct HashableVersion: Encodable {
            let extractors: [(String, String)]
            let windowing: WindowingParams
            let normalization: NormalizationParams

            enum CodingKeys: String, CodingKey {
                case extractors, windowing, normalization
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Dictionary(uniqueKeysWithValues: extractors), forKey: .extractors)
                try container.encode(windowing, forKey: .windowing)
                try container.encode(normalization, forKey: .normalization)
            }
        }

        let hashable = HashableVersion(
            extractors: sortedExtractors,
            windowing: windowingParams,
            normalization: normalizationParams
        )

        guard let data = try? encoder.encode(hashable) else {
            return "invalid"
        }

        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
