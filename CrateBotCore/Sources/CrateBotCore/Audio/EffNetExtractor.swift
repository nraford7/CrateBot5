import AVFoundation
import CoreML

/// Extracts 1280-dimensional embeddings using Discogs-EffNet CoreML model
/// Also provides 400-dimensional genre activations as a secondary output
public final class EffNetExtractor: FeatureExtractor, @unchecked Sendable {
    public let id = "effnet"
    public let version = "v1"
    public let featureCount = 1280

    private let model: MLModel
    private let melGenerator: MelSpectrogramGenerator

    /// Target sample rate for EffNet (16kHz)
    public static let targetSampleRate: Double = 16000

    // Model input/output names (discovered from compiled model)
    private static let inputName = "input_1"
    private static let embeddingsOutputName = "input_295"
    private static let genreOutputName = "var_1261"

    public init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        // Try multiple locations for the CoreML model
        // Priority: compiled (.mlmodelc) first, then uncompiled (.mlpackage)

        // 1. Try compiled model from Bundle.module (Swift Package resources - Xcode compiles during build)
        if let url = Bundle.module.url(forResource: "Discogs_EffNet", withExtension: "mlmodelc") {
            self.model = try MLModel(contentsOf: url, configuration: config)
            self.melGenerator = MelSpectrogramGenerator()
            return
        }

        // 2. Try uncompiled model from Bundle.module and compile it
        if let url = Bundle.module.url(forResource: "Discogs_EffNet", withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL, configuration: config)
            self.melGenerator = MelSpectrogramGenerator()
            return
        }

        // 3. Try compiled model from Bundle.main
        if let url = Bundle.main.url(forResource: "Discogs_EffNet", withExtension: "mlmodelc") {
            self.model = try MLModel(contentsOf: url, configuration: config)
            self.melGenerator = MelSpectrogramGenerator()
            return
        }

        // 4. Try uncompiled model from Bundle.main
        if let url = Bundle.main.url(forResource: "Discogs_EffNet", withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL, configuration: config)
            self.melGenerator = MelSpectrogramGenerator()
            return
        }

        // Model not found
        throw EffNetError.modelNotFound
    }

    public func extract(from buffer: AVAudioPCMBuffer) async throws -> [Float] {
        let result = try await extractWithGenres(from: buffer)
        return result.embeddings
    }

    /// Extract both embeddings and genre activations
    /// - Parameter buffer: Audio buffer at 16kHz mono
    /// - Returns: Tuple of (1280-dim embeddings, 400-dim genre activations)
    public func extractWithGenres(from buffer: AVAudioPCMBuffer) async throws -> (embeddings: [Float], genreActivations: [Float]) {
        // Generate mel spectrogram
        let melSpec = try melGenerator.generate(from: buffer)
        let flatMelSpec = melGenerator.flatten(melSpec)

        // Create MLMultiArray input [1, 128, 96] = [batch, time_frames, mel_bands]
        // MelSpectrogramGenerator now produces 128 time frames x 96 mel bands, flattened in correct order
        let inputArray = try MLMultiArray(shape: [1, 128, 96], dataType: .float32)
        for (i, value) in flatMelSpec.enumerated() {
            inputArray[i] = NSNumber(value: value)
        }

        // Create feature provider
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            Self.inputName: MLFeatureValue(multiArray: inputArray)
        ])

        // Run inference
        let output = try await model.prediction(from: provider)

        // Extract embeddings
        guard let embeddingsOutput = output.featureValue(for: Self.embeddingsOutputName),
              let embeddingsArray = embeddingsOutput.multiArrayValue else {
            throw EffNetError.invalidOutput("embeddings")
        }

        // Extract genre activations
        guard let genreOutput = output.featureValue(for: Self.genreOutputName),
              let genreArray = genreOutput.multiArrayValue else {
            throw EffNetError.invalidOutput("genres")
        }

        // Convert to [Float]
        var embeddings = [Float](repeating: 0, count: featureCount)
        for i in 0..<featureCount {
            embeddings[i] = embeddingsArray[i].floatValue
        }

        var genreActivations = [Float](repeating: 0, count: 400)
        for i in 0..<400 {
            genreActivations[i] = genreArray[i].floatValue
        }

        return (embeddings, genreActivations)
    }

    // MARK: - Batch Extraction

    /// Extract embeddings from multiple mel spectrograms in a single batch for improved performance.
    /// Batching maximizes Neural Engine utilization on Apple Silicon.
    ///
    /// - Parameter melSpectrograms: Array of flattened mel spectrograms (each 128*96 = 12288 floats)
    /// - Returns: Array of 1280-dimensional embeddings, one per input
    public func extractBatch(from melSpectrograms: [[Float]]) async throws -> [[Float]] {
        guard !melSpectrograms.isEmpty else { return [] }

        let batchSize = melSpectrograms.count
        let melSize = 128 * 96  // Expected size per spectrogram

        // Create batched MLMultiArray input [batchSize, 128, 96]
        let inputArray = try MLMultiArray(shape: [NSNumber(value: batchSize), 128, 96], dataType: .float32)

        // Fill the batch array
        for (batchIdx, melSpec) in melSpectrograms.enumerated() {
            guard melSpec.count == melSize else {
                throw EffNetError.invalidOutput("mel spectrogram size mismatch: expected \(melSize), got \(melSpec.count)")
            }

            let offset = batchIdx * melSize
            for (i, value) in melSpec.enumerated() {
                inputArray[offset + i] = NSNumber(value: value)
            }
        }

        // Create feature provider
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            Self.inputName: MLFeatureValue(multiArray: inputArray)
        ])

        // Run batched inference
        let output = try await model.prediction(from: provider)

        // Extract embeddings
        guard let embeddingsOutput = output.featureValue(for: Self.embeddingsOutputName),
              let embeddingsArray = embeddingsOutput.multiArrayValue else {
            throw EffNetError.invalidOutput("embeddings")
        }

        // Parse batched output - shape should be [batchSize, 1280]
        var results: [[Float]] = []
        for batchIdx in 0..<batchSize {
            var embeddings = [Float](repeating: 0, count: featureCount)
            let offset = batchIdx * featureCount
            for i in 0..<featureCount {
                embeddings[i] = embeddingsArray[offset + i].floatValue
            }
            results.append(embeddings)
        }

        return results
    }

    /// Preprocess audio buffer to mel spectrogram without running inference.
    /// Use this to prepare batches for `extractBatch`.
    ///
    /// - Parameter buffer: Audio buffer at 16kHz mono
    /// - Returns: Flattened mel spectrogram ready for batched inference
    public func prepareMelSpectrogram(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        let melSpec = try melGenerator.generate(from: buffer)
        return melGenerator.flatten(melSpec)
    }
}

// MARK: - Errors

public enum EffNetError: LocalizedError {
    case modelNotFound
    case invalidOutput(String)
    case resamplingFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Discogs_EffNet.mlpackage not found in bundle"
        case .invalidOutput(let name):
            return "Model produced invalid \(name) output"
        case .resamplingFailed:
            return "Failed to resample audio to 16kHz"
        }
    }
}
