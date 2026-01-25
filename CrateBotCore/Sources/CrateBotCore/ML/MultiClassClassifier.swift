import Foundation
import CoreML

public actor MultiClassClassifier {

    public struct Prediction: Sendable {
        public let groupName: String
        public let predictedClass: String
        public let confidence: Float
        public let classProbabilities: [String: Float]
    }

    public let groupName: String
    public let classes: [String]
    public let featureCount: Int

    private let model: MLModel

    public init(groupName: String, classes: [String], modelURL: URL, featureCount: Int = 1680) throws {
        self.groupName = groupName
        self.classes = classes
        self.featureCount = featureCount

        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try MLModel.compileModel(at: modelURL)
        }
        self.model = try MLModel(contentsOf: compiledURL)
    }

    public func predict(features: [Float]) throws -> Prediction {
        guard features.count >= featureCount else {
            throw ClassifierError.invalidFeatureCount(expected: featureCount, got: features.count)
        }

        var featureDict: [String: MLFeatureValue] = [:]
        for i in 0..<featureCount {
            featureDict["f\(i)"] = MLFeatureValue(double: Double(features[i]))
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let prediction = try model.prediction(from: provider)

        guard let predictedClass = prediction.featureValue(for: "label")?.stringValue else {
            throw ClassifierError.missingPrediction
        }

        var classProbabilities: [String: Float] = [:]
        if let probsDict = prediction.featureValue(for: "labelProbability")?.dictionaryValue {
            for (key, value) in probsDict {
                if let className = key as? String, let prob = value as? Double {
                    classProbabilities[className] = Float(prob)
                }
            }
        }

        let confidence = classProbabilities[predictedClass] ?? 0.0

        return Prediction(
            groupName: groupName,
            predictedClass: predictedClass,
            confidence: confidence,
            classProbabilities: classProbabilities
        )
    }

    public enum ClassifierError: Error, LocalizedError {
        case invalidFeatureCount(expected: Int, got: Int)
        case missingPrediction

        public var errorDescription: String? {
            switch self {
            case .invalidFeatureCount(let expected, let got):
                return "Feature count mismatch: expected \(expected), got \(got)"
            case .missingPrediction:
                return "Model did not return a prediction"
            }
        }
    }
}
