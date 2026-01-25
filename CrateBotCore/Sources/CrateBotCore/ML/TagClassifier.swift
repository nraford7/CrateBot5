import CoreML
import os.log

public enum TagClassifierError: Error, LocalizedError {
    case invalidOutput
    case featureDimensionMismatch(expected: Int, got: Int)
    case modelLoadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "Model produced invalid output format"
        case .featureDimensionMismatch(let expected, let got):
            return "Feature dimension mismatch: expected \(expected), got \(got)"
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        }
    }
}

/// Input format for the classifier
private enum ClassifierInputFormat {
    /// Single multiArray input (e.g., neural network models)
    case multiArray(inputKey: String, featureCount: Int)
    /// Tabular input with individual feature columns (e.g., BoostedTreeClassifier)
    case tabular(featureCount: Int)
}

/// Wrapper for CoreML binary classifier with proper MLFeatureProvider usage
public class TagClassifier: @unchecked Sendable {
    public let tagName: String
    public let threshold: Float

    private let compiledModel: MLModel
    private let inputFormat: ClassifierInputFormat
    private let probabilityOutputKey: String
    private let logger = Logger(subsystem: "com.cratebot", category: "TagClassifier")

    public init(tagName: String, modelURL: URL, threshold: Float) throws {
        self.tagName = tagName
        self.threshold = threshold

        // Load model - compile if needed (uncompiled .mlmodel vs compiled .mlmodelc)
        do {
            if modelURL.pathExtension == "mlmodelc" {
                // Already compiled
                self.compiledModel = try MLModel(contentsOf: modelURL)
            } else {
                // Uncompiled .mlmodel - compile it first
                let compiledURL = try MLModel.compileModel(at: modelURL)
                self.compiledModel = try MLModel(contentsOf: compiledURL)
            }
        } catch {
            throw TagClassifierError.modelLoadFailed(error.localizedDescription)
        }

        let description = compiledModel.modelDescription
        let inputs = description.inputDescriptionsByName

        // Detect input format
        if let inputKey = inputs.keys.first,
           let inputDescription = inputs[inputKey],
           let constraint = inputDescription.multiArrayConstraint {
            // Single multiArray input (neural network style)
            self.inputFormat = .multiArray(
                inputKey: inputKey,
                featureCount: constraint.shape.first?.intValue ?? 0
            )
        } else {
            // Tabular input (BoostedTreeClassifier style with f0, f1, f2, ...)
            // Count how many "fN" inputs exist
            let featureInputs = inputs.keys.filter { $0.hasPrefix("f") && Int($0.dropFirst()) != nil }
            guard !featureInputs.isEmpty else {
                throw TagClassifierError.modelLoadFailed("Model has no recognized input format")
            }
            self.inputFormat = .tabular(featureCount: featureInputs.count)
        }

        self.probabilityOutputKey = description.outputDescriptionsByName
            .first { $0.value.type == .dictionary }?.key ?? "probability"

        logger.debug("Loaded classifier for '\(tagName)' with threshold \(threshold)")
    }

    private var expectedFeatureCount: Int {
        switch inputFormat {
        case .multiArray(_, let featureCount):
            return featureCount
        case .tabular(let featureCount):
            return featureCount
        }
    }

    private func runPrediction(features: [Float]) throws -> Double {
        guard features.count == expectedFeatureCount else {
            throw TagClassifierError.featureDimensionMismatch(
                expected: expectedFeatureCount,
                got: features.count
            )
        }

        let inputProvider: MLFeatureProvider

        switch inputFormat {
        case .multiArray(let inputKey, _):
            // Create multiArray input
            let multiArray = try MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .float32)
            for (i, value) in features.enumerated() {
                multiArray[i] = NSNumber(value: value)
            }
            inputProvider = try MLDictionaryFeatureProvider(dictionary: [
                inputKey: MLFeatureValue(multiArray: multiArray)
            ])

        case .tabular:
            // Create dictionary with individual feature columns (f0, f1, f2, ...)
            var featureDict: [String: MLFeatureValue] = [:]
            for (i, value) in features.enumerated() {
                featureDict["f\(i)"] = MLFeatureValue(double: Double(value))
            }
            inputProvider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        }

        let output = try compiledModel.prediction(from: inputProvider)

        guard let probabilityDict = output.featureValue(for: probabilityOutputKey)?.dictionaryValue,
              let positiveProb = probabilityDict["positive"] as? Double else {
            throw TagClassifierError.invalidOutput
        }

        return positiveProb
    }

    public func predict(features: [Float]) throws -> Bool {
        let positiveProb = try runPrediction(features: features)
        let result = Float(positiveProb) > threshold
        logger.debug("'\(self.tagName)' prediction: \(positiveProb) -> \(result)")
        return result
    }

    public func predictWithConfidence(features: [Float]) throws -> (result: Bool, confidence: Float) {
        let positiveProb = try runPrediction(features: features)
        let confidence = Float(positiveProb)
        return (confidence > threshold, confidence)
    }
}

/// Predicts multiple tags using binary classifiers
public actor MultiLabelPredictor {
    private let classifiers: [TagClassifier]
    private let logger = Logger(subsystem: "com.cratebot", category: "MultiLabelPredictor")

    public init(classifiers: [TagClassifier]) {
        self.classifiers = classifiers
        logger.info("Initialized with \(classifiers.count) classifiers")
    }

    public func predict(features: [Float]) throws -> [String] {
        try classifiers
            .filter { try $0.predict(features: features) }
            .map { $0.tagName }
    }

    public func predictWithConfidences(features: [Float]) throws -> [(tag: String, confidence: Float)] {
        try classifiers.compactMap { classifier in
            let (result, confidence) = try classifier.predictWithConfidence(features: features)
            return result ? (classifier.tagName, confidence) : nil
        }
    }

    public func predictAll(features: [Float]) throws -> [(tag: String, confidence: Float, predicted: Bool)] {
        try classifiers.map { classifier in
            let (result, confidence) = try classifier.predictWithConfidence(features: features)
            return (classifier.tagName, confidence, result)
        }
    }
}
