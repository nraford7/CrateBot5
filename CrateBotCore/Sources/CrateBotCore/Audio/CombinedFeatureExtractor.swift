import AVFoundation

/// Combines multiple extractors for rich audio features.
/// Provides a unified interface for extracting and concatenating features
/// from EffNet (embeddings + genres) and optionally CLAP.
public actor CombinedFeatureExtractor {

    /// Configuration for which feature extractors to combine
    public enum FeatureConfig: String, Sendable, Codable, Equatable {
        case effnetOnly = "effnetOnly"           // 1280 dims
        case effnetPlusGenres = "effnetPlusGenres"     // 1680 dims (1280 + 400)
        case effnetGenresCLAP = "effnetGenresCLAP"     // 2192 dims (1280 + 400 + 512)
        case effnetGenresCLAPMAEST = "effnetGenresCLAPMAEST" // 2960 dims (1280 + 400 + 512 + 768)

        public var dimension: Int {
            switch self {
            case .effnetOnly: return 1280
            case .effnetPlusGenres: return 1680
            case .effnetGenresCLAP: return 2192
            case .effnetGenresCLAPMAEST: return 2960
            }
        }

        public var description: String {
            switch self {
            case .effnetOnly: return "EffNet (1280)"
            case .effnetPlusGenres: return "EffNet+Genres (1680)"
            case .effnetGenresCLAP: return "EffNet+Genres+CLAP (2192)"
            case .effnetGenresCLAPMAEST: return "EffNet+Genres+CLAP+MAEST (2960)"
            }
        }
    }

    private let effnetExtractor: EffNetExtractor
    private let clapExtractor: CLAPExtractor?
    private let maestExtractor: MAESTExtractor?
    private let config: FeatureConfig
    private let actualConfig: FeatureConfig

    /// Initialize the combined feature extractor
    /// - Parameter config: Which extractors to combine
    /// - Throws: If EffNet extractor cannot be initialized (CLAP/MAEST failure is non-fatal)
    public init(config: FeatureConfig = .effnetGenresCLAP) throws {
        self.config = config
        self.effnetExtractor = try EffNetExtractor()

        if config == .effnetGenresCLAPMAEST {
            // Try CLAP
            var clap: CLAPExtractor?
            do {
                clap = try CLAPExtractor()
            } catch {
                print("Warning: CLAP extractor unavailable (\(error.localizedDescription))")
            }
            self.clapExtractor = clap

            // Try MAEST
            var maest: MAESTExtractor?
            do {
                maest = try MAESTExtractor()
            } catch {
                print("Warning: MAEST extractor unavailable (\(error.localizedDescription))")
            }
            self.maestExtractor = maest

            // Determine effective config based on what loaded
            if clap != nil && maest != nil {
                self.actualConfig = .effnetGenresCLAPMAEST
            } else if clap != nil {
                self.actualConfig = .effnetGenresCLAP
            } else {
                self.actualConfig = .effnetPlusGenres
            }
        } else if config == .effnetGenresCLAP {
            do {
                self.clapExtractor = try CLAPExtractor()
                self.actualConfig = .effnetGenresCLAP
            } catch {
                print("Warning: CLAP extractor unavailable (\(error.localizedDescription)), falling back to EffNet+Genres")
                self.clapExtractor = nil
                self.actualConfig = .effnetPlusGenres
            }
            self.maestExtractor = nil
        } else {
            self.clapExtractor = nil
            self.maestExtractor = nil
            self.actualConfig = config
        }
    }

    /// The actual feature dimension based on available extractors
    public var featureDimension: Int {
        actualConfig.dimension
    }

    /// The requested configuration
    public var requestedConfig: FeatureConfig {
        config
    }

    /// The effective configuration (may differ if CLAP unavailable)
    public var effectiveConfig: FeatureConfig {
        actualConfig
    }

    /// Extract combined features from an audio buffer
    /// - Parameter buffer: Audio buffer (should be at 16kHz mono for EffNet compatibility)
    /// - Returns: Combined feature vector with dimension based on config
    public func extract(from buffer: AVAudioPCMBuffer) async throws -> [Float] {
        try await extract(from: buffer, augmentationConfig: nil)
    }

    /// Extract combined features with optional augmentation (used for training only)
    public func extract(
        from buffer: AVAudioPCMBuffer,
        augmentationConfig: AudioAugmenter.AugmentationConfig?
    ) async throws -> [Float] {
        switch actualConfig {
        case .effnetOnly:
            return try await effnetExtractor.extract(from: buffer, augmentationConfig: augmentationConfig)

        case .effnetPlusGenres:
            let (embeddings, genres) = try await effnetExtractor.extractWithGenres(from: buffer, augmentationConfig: augmentationConfig)
            return embeddings + genres

        case .effnetGenresCLAP:
            // Extract EffNet features
            let (embeddings, genres) = try await effnetExtractor.extractWithGenres(from: buffer, augmentationConfig: augmentationConfig)

            // Extract CLAP features (convert buffer to Float array)
            if let clap = clapExtractor {
                let audioSamples = extractFloatSamples(from: buffer)
                let sampleRate = Double(buffer.format.sampleRate)
                let clapEmbeddings = try await clap.extract(from: audioSamples, sampleRate: sampleRate, augmentationConfig: augmentationConfig)
                return embeddings + genres + clapEmbeddings  // 1280 + 400 + 512 = 2192
            } else {
                // Fallback to 1680 (shouldn't happen if actualConfig is correct)
                return embeddings + genres
            }

        case .effnetGenresCLAPMAEST:
            // Extract EffNet features
            let (embeddings, genres) = try await effnetExtractor.extractWithGenres(from: buffer, augmentationConfig: augmentationConfig)

            // Extract CLAP features
            var combined = embeddings + genres
            if let clap = clapExtractor {
                let audioSamples = extractFloatSamples(from: buffer)
                let sampleRate = Double(buffer.format.sampleRate)
                let clapEmbeddings = try await clap.extract(from: audioSamples, sampleRate: sampleRate, augmentationConfig: augmentationConfig)
                combined += clapEmbeddings
            }

            // Extract MAEST features
            if let maest = maestExtractor {
                let maestEmbeddings = try await maest.extract(from: buffer, augmentationConfig: augmentationConfig)
                combined += maestEmbeddings  // 1280 + 400 + 512 + 768 = 2960
            }

            return combined
        }
    }

    /// Extract combined features from a raw audio buffer
    /// - Parameters:
    ///   - audioBuffer: Audio samples as Float array
    ///   - sampleRate: Sample rate of the input audio
    /// - Returns: Combined feature vector with dimension based on config
    /// - Note: This method is useful when you already have audio as Float array
    public func extract(from audioBuffer: [Float], sampleRate: Double) async throws -> [Float] {
        // Convert Float array to AVAudioPCMBuffer for EffNet
        let buffer = try createPCMBuffer(from: audioBuffer, sampleRate: sampleRate)
        return try await extract(from: buffer)
    }

    // MARK: - Private Helpers

    /// Extract Float samples from an AVAudioPCMBuffer
    private func extractFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            // Mono: direct copy
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        } else {
            // Multi-channel: mix down to mono
            var monoSamples = [Float](repeating: 0, count: frameCount)
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                for i in 0..<frameCount {
                    monoSamples[i] += samples[i]
                }
            }
            // Normalize by channel count
            let scale = 1.0 / Float(channelCount)
            for i in 0..<frameCount {
                monoSamples[i] *= scale
            }
            return monoSamples
        }
    }

    /// Create an AVAudioPCMBuffer from Float samples
    private func createPCMBuffer(from samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw CombinedFeatureError.invalidFormat
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw CombinedFeatureError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channelData = buffer.floatChannelData else {
            throw CombinedFeatureError.bufferCreationFailed
        }

        for (index, sample) in samples.enumerated() {
            channelData[0][index] = sample
        }

        return buffer
    }
}

// MARK: - Errors

public enum CombinedFeatureError: Error, LocalizedError {
    case invalidFormat
    case bufferCreationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Failed to create audio format"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        }
    }
}
