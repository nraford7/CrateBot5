import Foundation
import os.log

/// Production `Stage1Predictor`: wraps the trained Stage 1 model set
/// (binary `TagClassifier`s + `MultiClassClassifier` groups) and emits the
/// exact values inference will feed Stage 2 — CALIBRATED, PRE-BOOST
/// confidences, mirroring TaggingEngine's pass-1 semantics
/// (`predictWithConfidence` → `confidenceCalibrator.calibrate`). No
/// co-occurrence boosting, no thresholding: Stage 2 sees raw calibrated
/// probabilities, the same distribution at training and at inference.
public struct ProductionStage1Predictor: Stage1Predictor {
    private let classifiers: [TagClassifier]
    private let groupClassifiers: [String: MultiClassClassifier]
    private let calibrator: ConfidenceCalibrator
    private let logger = Logger(subsystem: "com.cratebot.core", category: "ProductionStage1Predictor")

    /// Tag names of the wrapped binary classifiers (sorted, for diagnostics).
    public var binaryTagNames: [String] {
        classifiers.map(\.tagName).sorted()
    }

    public init(
        classifiers: [TagClassifier],
        groupClassifiers: [String: MultiClassClassifier],
        calibrator: ConfidenceCalibrator = ConfidenceCalibrator()
    ) {
        self.classifiers = classifiers
        self.groupClassifiers = groupClassifiers
        self.calibrator = calibrator
    }

    /// Load the Stage 1 model set from a trained model directory.
    ///
    /// File rules mirror TaggingEngine's loader: every `.mlmodel` /
    /// `.mlmodelc` is a binary classifier unless suffixed `_multiclass`
    /// (loaded per metadata tag groups) or `_judgment` (Stage 2 output —
    /// never an input to itself).
    ///
    /// - Parameters:
    ///   - modelDirectory: Directory containing the trained Stage 1 models.
    ///   - metadata: Model metadata; supplies the multi-class groups, the
    ///     feature dimension, and the calibrator temperature. nil loads
    ///     binary classifiers only with a default calibrator.
    public static func load(
        from modelDirectory: URL,
        metadata: ModelMetadata?
    ) throws -> ProductionStage1Predictor {
        let logger = Logger(subsystem: "com.cratebot.core", category: "ProductionStage1Predictor")
        let fileManager = FileManager.default

        let contents = try fileManager.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: nil
        )
        let modelFiles = contents.filter {
            $0.pathExtension == "mlmodel" || $0.pathExtension == "mlmodelc"
        }

        var classifiers: [TagClassifier] = []
        for modelURL in modelFiles {
            let name = modelURL.deletingPathExtension().lastPathComponent
            guard !name.hasSuffix("_multiclass"), !name.hasSuffix("_judgment") else { continue }
            do {
                // Threshold is irrelevant for confidence emission; 0.5 matches
                // TaggingEngine's loading default.
                classifiers.append(try TagClassifier(tagName: name, modelURL: modelURL, threshold: 0.5))
            } catch {
                logger.warning("Failed to load Stage 1 classifier '\(name)': \(error.localizedDescription)")
            }
        }

        var groupClassifiers: [String: MultiClassClassifier] = [:]
        if let metadata = metadata {
            for groupInfo in metadata.tagGroups {
                let candidates = [
                    modelDirectory.appendingPathComponent("\(groupInfo.groupName)_multiclass.mlmodelc"),
                    modelDirectory.appendingPathComponent("\(groupInfo.groupName)_multiclass.mlmodel")
                ]
                guard let modelURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
                    logger.warning("Multi-class model not found for group '\(groupInfo.groupName)'")
                    continue
                }
                do {
                    groupClassifiers[groupInfo.groupName] = try MultiClassClassifier(
                        groupName: groupInfo.groupName,
                        classes: groupInfo.classes,
                        modelURL: modelURL,
                        featureCount: metadata.featureDimension
                    )
                } catch {
                    logger.warning("Failed to load multi-class '\(groupInfo.groupName)': \(error.localizedDescription)")
                }
            }
        }

        let calibrator: ConfidenceCalibrator
        if let temperature = metadata?.calibratorTemperature {
            calibrator = ConfidenceCalibrator(temperature: temperature, smoothingFactor: 0.1)
        } else {
            calibrator = ConfidenceCalibrator()
        }

        return ProductionStage1Predictor(
            classifiers: classifiers,
            groupClassifiers: groupClassifiers,
            calibrator: calibrator
        )
    }

    public func confidences(
        features: [Float]
    ) async throws -> (binary: [String: Float], groups: [String: [String: Float]]) {
        var binary: [String: Float] = [:]
        for classifier in classifiers {
            do {
                let (_, rawConfidence) = try classifier.predictWithConfidence(features: features)
                binary[classifier.tagName] = calibrator.calibrate(rawConfidence)
            } catch {
                // Mirror TaggingEngine pass-1: log and omit. A consistently
                // failing classifier drops out of the schema for every row;
                // an intermittently failing one produces rows the judgment
                // trainer rejects on schema mismatch.
                logger.error("Stage 1 classifier '\(classifier.tagName)' failed: \(error.localizedDescription)")
            }
        }

        var groups: [String: [String: Float]] = [:]
        for (groupName, classifier) in groupClassifiers {
            do {
                let prediction = try await classifier.predict(features: features)
                groups[groupName] = prediction.classProbabilities
            } catch {
                logger.error("Stage 1 multi-class group '\(groupName)' failed: \(error.localizedDescription)")
            }
        }

        return (binary, groups)
    }
}
