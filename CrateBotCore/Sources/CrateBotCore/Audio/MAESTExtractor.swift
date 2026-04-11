import AVFoundation
import CoreML

/// Extracts 768-dimensional embeddings using MAEST (Music Audio Efficient Spectrogram Transformer).
/// MAEST captures high-level musical structure and semantics complementary to EffNet and CLAP.
public actor MAESTExtractor {

    public static let embeddingDimension = 768

    /// Target sample rate for MAEST (16kHz, same as EffNet)
    public static let targetSampleRate: Double = 16000

    // TODO: Update these after running convert_maest.py — the names come from the ONNX model
    private static let inputName = "input"          // TODO: verify from CoreML model spec
    private static let outputName = "embedding"     // TODO: verify from CoreML model spec

    private let model: MLModel
    private let melGenerator: MelSpectrogramGenerator

    public init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        // Try multiple locations for the CoreML model
        var modelURL: URL?

        // 1. Try compiled model from Bundle.module
        if let url = Bundle.module.url(forResource: "MAEST", withExtension: "mlmodelc") {
            modelURL = url
        }
        // 2. Try uncompiled model from Bundle.module
        else if let url = Bundle.module.url(forResource: "MAEST", withExtension: "mlpackage") {
            modelURL = url
        }
        // 3. Try compiled model from Bundle.main
        else if let url = Bundle.main.url(forResource: "MAEST", withExtension: "mlmodelc") {
            modelURL = url
        }
        // 4. Try uncompiled model from Bundle.main
        else if let url = Bundle.main.url(forResource: "MAEST", withExtension: "mlpackage") {
            modelURL = url
        }

        guard let url = modelURL else {
            throw MAESTError.modelNotFound
        }

        let compiledURL: URL
        if url.pathExtension == "mlmodelc" {
            compiledURL = url
        } else {
            compiledURL = try MLModel.compileModel(at: url)
        }

        self.model = try MLModel(contentsOf: compiledURL, configuration: config)
        self.melGenerator = MelSpectrogramGenerator()
    }

    /// Extract 768-dim MAEST embeddings from an audio buffer
    /// - Parameters:
    ///   - buffer: Audio buffer at 16kHz mono
    ///   - augmentationConfig: Optional augmentation for training
    /// - Returns: 768-dimensional embedding vector
    public func extract(
        from buffer: AVAudioPCMBuffer,
        augmentationConfig: AudioAugmenter.AugmentationConfig? = nil
    ) async throws -> [Float] {
        // Generate mel spectrogram using shared generator
        var melSpec = try melGenerator.generate(from: buffer)
        if let augmentationConfig = augmentationConfig {
            melSpec = AudioAugmenter.applySpecAugment(to: melSpec, config: augmentationConfig)
        }
        let flatMelSpec = melGenerator.flatten(melSpec)

        // TODO: Verify input shape after model conversion
        // MAEST typically expects [1, 1, 96, time_frames] or [1, 96, time_frames]
        // Using [1, 128, 96] to match EffNet mel generator output for now
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
        guard let embeddingOutput = output.featureValue(for: Self.outputName),
              let embeddingArray = embeddingOutput.multiArrayValue else {
            throw MAESTError.invalidOutput("embedding")
        }

        // Convert to [Float]
        var embeddings = [Float](repeating: 0, count: Self.embeddingDimension)
        for i in 0..<Self.embeddingDimension {
            embeddings[i] = embeddingArray[i].floatValue
        }

        return embeddings
    }
}

// MARK: - Errors

public enum MAESTError: Error, LocalizedError {
    case modelNotFound
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "MAEST.mlpackage not found in bundle"
        case .invalidOutput(let name):
            return "MAEST model produced invalid \(name) output"
        }
    }
}
