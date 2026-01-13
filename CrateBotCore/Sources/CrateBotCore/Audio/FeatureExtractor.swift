import AVFoundation

/// Protocol for audio feature extractors
public protocol FeatureExtractor: Sendable {
    /// Unique identifier for this extractor
    var id: String { get }

    /// Version string for cache invalidation
    var version: String { get }

    /// Number of features this extractor produces
    var featureCount: Int { get }

    /// Extract features from an audio buffer
    func extract(from buffer: AVAudioPCMBuffer) async throws -> [Float]
}

/// Errors that can occur during feature extraction
public enum FeatureExtractionError: Error, LocalizedError {
    case invalidBuffer
    case insufficientData(required: Int, got: Int)
    case extractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBuffer:
            return "Invalid audio buffer provided"
        case .insufficientData(let required, let got):
            return "Insufficient audio data: need \(required) samples, got \(got)"
        case .extractionFailed(let reason):
            return "Feature extraction failed: \(reason)"
        }
    }
}
