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

/// Wrapper for CoreML binary classifier with proper MLFeatureProvider usage
public class TagClassifier: @unchecked Sendable {
    public let tagName: String
    public let threshold: Float

    private let compiledModel: MLModel
    private let featureInputKey: String
    private let probabilityOutputKey: String
    private let expectedFeatureCount: Int
    private let logger = Logger(subsystem: "com.cratebot", category: "TagClassifier")

    public init(tagName: String, modelURL: URL, threshold: Float) throws {
        self.tagName = tagName
        self.threshold = threshold

        do {
            self.compiledModel = try MLModel(contentsOf: modelURL)
        } catch {
            throw TagClassifierError.modelLoadFailed(error.localizedDescription)
        }

        let description = compiledModel.modelDescription

        guard let inputKey = description.inputDescriptionsByName.keys.first,
              let inputDescription = description.inputDescriptionsByName[inputKey] else {
            throw TagClassifierError.modelLoadFailed("Model must have at least one input")
        }

        guard let constraint = inputDescription.multiArrayConstraint else {
            throw TagClassifierError.modelLoadFailed("Model input must be multiArray type")
        }

        self.featureInputKey = inputKey
        self.expectedFeatureCount = constraint.shape.first?.intValue ?? 0

        self.probabilityOutputKey = description.outputDescriptionsByName
            .first { $0.value.type == .dictionary }?.key ?? "probability"

        logger.debug("Loaded classifier for '\(tagName)' with threshold \(threshold)")
    }

    private func runPrediction(features: [Float]) throws -> Double {
        guard features.count == expectedFeatureCount else {
            throw TagClassifierError.featureDimensionMismatch(
                expected: expectedFeatureCount,
                got: features.count
            )
        }

        let multiArray = try MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .float32)
        for (i, value) in features.enumerated() {
            multiArray[i] = NSNumber(value: value)
        }

        let inputProvider = try MLDictionaryFeatureProvider(dictionary: [
            featureInputKey: MLFeatureValue(multiArray: multiArray)
        ])

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
