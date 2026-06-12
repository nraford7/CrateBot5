import CoreML
import os.log

public enum TagClassifierError: Error, LocalizedError {
    case invalidOutput
    case featureDimensionMismatch(expected: Int, got: Int)
    case modelLoadFailed(String)
    case inputFormatMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "Model produced invalid output format"
        case .featureDimensionMismatch(let expected, let got):
            return "Feature dimension mismatch: expected \(expected), got \(got)"
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .inputFormatMismatch(let reason):
            return "Input format mismatch: \(reason)"
        }
    }
}

/// Input format for the classifier
private enum ClassifierInputFormat {
    /// Single multiArray input (e.g., neural network models)
    case multiArray(inputKey: String, featureCount: Int)
    /// Tabular input with individual feature columns (e.g., BoostedTreeClassifier)
    case tabular(featureCount: Int)
    /// Tabular input with NAMED scalar columns — Stage 2 judgment models
    /// trained on JudgmentFeatureVector columns (`bin_*`, `grp_*`, `bpm`,
    /// `duration`) rather than positional `f0...fN` audio features.
    case namedTabular(columns: [String])
}

/// Wrapper for CoreML binary classifier with proper MLFeatureProvider usage
public class TagClassifier: @unchecked Sendable {
    public let tagName: String
    public let threshold: Float

    private let compiledModel: MLModel
    private let inputFormat: ClassifierInputFormat
    private let probabilityOutputKey: String
    private let logger = Logger(subsystem: "com.cratebot", category: "TagClassifier")

    /// Extract feature count from a multiarray shape
    /// Handles shapes like [1680], [1, 1680], [1, 1, 1680]
    /// Returns the last non-1 dimension, or the last dimension if all are 1
    public static func extractFeatureCount(from shape: [NSNumber]) -> Int {
        // Find the last dimension > 1, or use the last dimension
        for dim in shape.reversed() {
            let value = dim.intValue
            if value > 1 {
                return value
            }
        }
        // All dimensions are 1, return the last one
        return shape.last?.intValue ?? 0
    }

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
            // Use helper to correctly parse shape like [1, N] or [N]
            let featureCount = Self.extractFeatureCount(from: constraint.shape)
            self.inputFormat = .multiArray(
                inputKey: inputKey,
                featureCount: featureCount
            )
        } else {
            // Tabular input (BoostedTreeClassifier style with f0, f1, f2, ...)
            // Count how many "fN" inputs exist
            let featureInputs = inputs.keys.filter { $0.hasPrefix("f") && Int($0.dropFirst()) != nil }
            if !featureInputs.isEmpty {
                self.inputFormat = .tabular(featureCount: featureInputs.count)
            } else if !inputs.isEmpty,
                      inputs.values.allSatisfy({ $0.type == .double || $0.type == .int64 }) {
                // Named scalar columns (Stage 2 judgment models)
                self.inputFormat = .namedTabular(columns: inputs.keys.sorted())
            } else {
                throw TagClassifierError.modelLoadFailed("Model has no recognized input format")
            }
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
        case .namedTabular(let columns):
            return columns.count
        }
    }

    private func runPrediction(features: [Float]) throws -> Double {
        if case .namedTabular = inputFormat {
            throw TagClassifierError.inputFormatMismatch(
                "'\(tagName)' takes named feature columns — use predictWithConfidence(namedFeatures:)")
        }
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

        case .namedTabular:
            // Guarded above — named models never take a positional vector.
            throw TagClassifierError.inputFormatMismatch(
                "'\(tagName)' takes named feature columns — use predictWithConfidence(namedFeatures:)")
        }

        return try extractPositiveProbability(from: inputProvider)
    }

    /// Run the model and read the "positive" class probability — the shared
    /// label convention across Stage 1 binary and Stage 2 judgment models.
    private func extractPositiveProbability(from inputProvider: MLFeatureProvider) throws -> Double {
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

    /// Predict from NAMED feature columns (Stage 2 judgment models).
    /// Every model input column must be present in `namedFeatures`;
    /// a missing column throws rather than silently substituting a value.
    public func predictWithConfidence(namedFeatures: [String: Float]) throws -> (result: Bool, confidence: Float) {
        guard case .namedTabular(let columns) = inputFormat else {
            throw TagClassifierError.inputFormatMismatch(
                "'\(tagName)' takes a positional feature vector — use predictWithConfidence(features:)")
        }

        var featureDict: [String: MLFeatureValue] = [:]
        for column in columns {
            guard let value = namedFeatures[column] else {
                throw TagClassifierError.inputFormatMismatch(
                    "'\(tagName)' is missing feature column '\(column)'")
            }
            featureDict[column] = MLFeatureValue(double: Double(value))
        }

        let inputProvider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let confidence = Float(try extractPositiveProbability(from: inputProvider))
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
