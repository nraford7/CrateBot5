import Foundation
import CoreML

/// Runs Essentia pre-trained classification heads on EffNet embeddings
public final class EssentiaClassifier: @unchecked Sendable {

    private let moodThemeModel: MLModel
    private let instrumentModel: MLModel

    // Model I/O names
    private static let inputName = "input_1"
    private static let outputName = "var_17"

    public init() throws {
        // Load mood/theme model
        guard let moodURL = Bundle.module.url(forResource: "Jamendo_MoodTheme", withExtension: "mlpackage") else {
            throw EssentiaClassifierError.modelNotFound("Jamendo_MoodTheme")
        }

        // Load instrument model
        guard let instURL = Bundle.module.url(forResource: "Jamendo_Instrument", withExtension: "mlpackage") else {
            throw EssentiaClassifierError.modelNotFound("Jamendo_Instrument")
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        let moodCompiled = try MLModel.compileModel(at: moodURL)
        let instCompiled = try MLModel.compileModel(at: instURL)

        self.moodThemeModel = try MLModel(contentsOf: moodCompiled, configuration: config)
        self.instrumentModel = try MLModel(contentsOf: instCompiled, configuration: config)
    }

    /// Predict mood/theme from EffNet embeddings
    public func predictMoodTheme(embeddings: [Float]) async throws -> [String: Float] {
        let output = try await runModel(moodThemeModel, embeddings: embeddings, outputSize: 56)
        return Dictionary(uniqueKeysWithValues: zip(EssentiaLabels.moodTheme, output))
    }

    /// Predict instruments from EffNet embeddings
    public func predictInstruments(embeddings: [Float]) async throws -> [String: Float] {
        let output = try await runModel(instrumentModel, embeddings: embeddings, outputSize: 40)
        return Dictionary(uniqueKeysWithValues: zip(EssentiaLabels.instruments, output))
    }

    /// Convert genre activations (from EffNet) to labeled predictions
    public func labelGenres(activations: [Float]) -> [String: Float] {
        // Apply sigmoid to convert logits to probabilities
        let probabilities = activations.map { 1.0 / (1.0 + exp(-$0)) }
        let labels = EssentiaLabels.genres

        var predictions: [String: Float] = [:]
        for (i, prob) in probabilities.enumerated() where i < labels.count {
            predictions[labels[i]] = prob
        }
        return predictions
    }

    /// Get top N predictions from a prediction dictionary
    public func topPredictions(_ predictions: [String: Float], count: Int = 5, threshold: Float = 0.1) -> [(tag: String, probability: Float)] {
        return predictions
            .filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { (tag: $0.key, probability: $0.value) }
    }

    // MARK: - Private

    private func runModel(_ model: MLModel, embeddings: [Float], outputSize: Int) async throws -> [Float] {
        guard embeddings.count == 1280 else {
            throw EssentiaClassifierError.invalidInput(expected: 1280, got: embeddings.count)
        }

        // Create input array [1, 1280]
        let inputArray = try MLMultiArray(shape: [1, 1280], dataType: .float32)
        for (i, value) in embeddings.enumerated() {
            inputArray[i] = NSNumber(value: value)
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            Self.inputName: MLFeatureValue(multiArray: inputArray)
        ])

        let output = try await model.prediction(from: provider)

        guard let outputValue = output.featureValue(for: Self.outputName),
              let outputArray = outputValue.multiArrayValue else {
            throw EssentiaClassifierError.invalidOutput
        }

        // Convert to [Float] - outputs are already sigmoid activated
        var result = [Float](repeating: 0, count: outputSize)
        for i in 0..<outputSize {
            result[i] = outputArray[i].floatValue
        }

        return result
    }
}

// MARK: - Errors

public enum EssentiaClassifierError: LocalizedError {
    case modelNotFound(String)
    case invalidInput(expected: Int, got: Int)
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "\(name).mlpackage not found in bundle"
        case .invalidInput(let expected, let got):
            return "Invalid embedding size: expected \(expected), got \(got)"
        case .invalidOutput:
            return "Model produced invalid output"
        }
    }
}
