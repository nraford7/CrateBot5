import Foundation
import CreateML
import TabularData
import os.log

/// Configuration for model training
public struct TrainingConfig: Sendable {
    /// Fraction of data to use for validation (0.0 - 1.0)
    public let validationSplit: Double

    /// Minimum samples required per tag to train a classifier
    public let minSamplesPerTag: Int

    /// Maximum ratio of negative to positive samples
    public let maxNegativeRatio: Double

    /// Random seed for reproducible training
    public let randomSeed: Int

    public init(
        validationSplit: Double = 0.2,
        minSamplesPerTag: Int = 50,
        maxNegativeRatio: Double = 3.0,
        randomSeed: Int = 42
    ) {
        self.validationSplit = validationSplit
        self.minSamplesPerTag = minSamplesPerTag
        self.maxNegativeRatio = maxNegativeRatio
        self.randomSeed = randomSeed
    }
}

/// Result of training a single tag classifier
public struct TrainingResult: Sendable {
    /// The tag this model was trained for
    public let tag: String

    /// URL where the model was saved
    public let modelURL: URL

    /// Accuracy on the training set
    public let trainingAccuracy: Double

    /// Accuracy on the validation set
    public let validationAccuracy: Double

    /// Number of positive examples used
    public let positiveCount: Int

    /// Number of negative examples used
    public let negativeCount: Int

    public init(
        tag: String,
        modelURL: URL,
        trainingAccuracy: Double,
        validationAccuracy: Double,
        positiveCount: Int,
        negativeCount: Int
    ) {
        self.tag = tag
        self.modelURL = modelURL
        self.trainingAccuracy = trainingAccuracy
        self.validationAccuracy = validationAccuracy
        self.positiveCount = positiveCount
        self.negativeCount = negativeCount
    }
}

/// Progress information during training
public struct TrainingProgress: Sendable {
    /// Current phase of training
    public enum Phase: Sendable {
        case preparing
        case training
        case validating
        case saving
        case complete
    }

    /// Current phase
    public let phase: Phase

    /// Tag currently being trained (nil if not training a specific tag)
    public let currentTag: String?

    /// Number of tags completed
    public let tagsCompleted: Int

    /// Total number of tags to train
    public let totalTags: Int

    public init(phase: Phase, currentTag: String?, tagsCompleted: Int, totalTags: Int) {
        self.phase = phase
        self.currentTag = currentTag
        self.tagsCompleted = tagsCompleted
        self.totalTags = totalTags
    }

    /// Progress as a fraction (0.0 to 1.0)
    public var fraction: Double {
        guard totalTags > 0 else { return 0.0 }
        return Double(tagsCompleted) / Double(totalTags)
    }
}

/// Errors that can occur during training
public enum TrainerError: Error, LocalizedError {
    case insufficientData(tag: String, count: Int, required: Int)
    case noFeaturesAvailable
    case trainingFailed(tag: String, reason: String)
    case saveFailed(tag: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .insufficientData(let tag, let count, let required):
            return "Insufficient data for tag '\(tag)': \(count) samples, \(required) required"
        case .noFeaturesAvailable:
            return "No tracks with features available for training"
        case .trainingFailed(let tag, let reason):
            return "Training failed for tag '\(tag)': \(reason)"
        case .saveFailed(let tag, let reason):
            return "Failed to save model for tag '\(tag)': \(reason)"
        }
    }
}

/// Actor for training binary classifiers using CreateML
public actor ModelTrainer {
    private let dataGenerator: BinaryTrainingDataGenerator
    private let logger = Logger(subsystem: "com.cratebot", category: "ModelTrainer")

    public init(dataGenerator: BinaryTrainingDataGenerator = BinaryTrainingDataGenerator()) {
        self.dataGenerator = dataGenerator
    }

    /// Train binary classifiers for specified tags
    /// - Parameters:
    ///   - tracks: Array of tagged tracks with features
    ///   - tags: Tags to train classifiers for
    ///   - outputDirectory: Directory to save trained models
    ///   - config: Training configuration
    ///   - progress: Optional progress callback
    /// - Returns: Array of training results for successfully trained models
    public func trainModels(
        from tracks: [TaggedTrack],
        tags: [String],
        outputDirectory: URL,
        config: TrainingConfig = TrainingConfig(),
        progress: ((TrainingProgress) async -> Void)? = nil
    ) async throws -> [TrainingResult] {
        // Filter tracks that have features
        let tracksWithFeatures = tracks.filter { $0.features != nil && !$0.features!.isEmpty }

        guard !tracksWithFeatures.isEmpty else {
            throw TrainerError.noFeaturesAvailable
        }

        // Determine feature count from first track
        let featureCount = tracksWithFeatures[0].features!.count

        // Create output directory if needed
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var results: [TrainingResult] = []

        for (index, tag) in tags.enumerated() {
            // Report preparing phase
            await progress?(TrainingProgress(
                phase: .preparing,
                currentTag: tag,
                tagsCompleted: index,
                totalTags: tags.count
            ))

            // Generate balanced training data
            guard let (positive, negative) = dataGenerator.generateTrainingData(for: tag, from: tracksWithFeatures) else {
                logger.info("Skipping tag '\(tag)': insufficient data")
                continue
            }

            logger.info("Training '\(tag)' with \(positive.count) positive, \(negative.count) negative samples")

            // Report training phase
            await progress?(TrainingProgress(
                phase: .training,
                currentTag: tag,
                tagsCompleted: index,
                totalTags: tags.count
            ))

            do {
                // Prepare DataFrame
                let dataFrame = try prepareDataFrame(
                    for: tag,
                    from: positive + negative,
                    featureCount: featureCount
                )

                // Split data for training and validation
                let (trainingData, validationData) = splitData(
                    dataFrame,
                    validationSplit: config.validationSplit,
                    seed: config.randomSeed
                )

                // Train the classifier
                let classifier = try MLClassifier(
                    trainingData: trainingData,
                    targetColumn: "label"
                )

                // Report validating phase
                await progress?(TrainingProgress(
                    phase: .validating,
                    currentTag: tag,
                    tagsCompleted: index,
                    totalTags: tags.count
                ))

                // Calculate accuracies
                let trainingAccuracy = calculateAccuracy(classifier: classifier, data: trainingData)
                let validationAccuracy = calculateAccuracy(classifier: classifier, data: validationData)

                logger.info("'\(tag)' - Training accuracy: \(trainingAccuracy), Validation accuracy: \(validationAccuracy)")

                // Report saving phase
                await progress?(TrainingProgress(
                    phase: .saving,
                    currentTag: tag,
                    tagsCompleted: index,
                    totalTags: tags.count
                ))

                // Save the model
                let sanitizedTagName = sanitizeFileName(tag)
                let modelURL = outputDirectory.appendingPathComponent("\(sanitizedTagName).mlmodel")

                try classifier.write(to: modelURL, metadata: nil)

                let result = TrainingResult(
                    tag: tag,
                    modelURL: modelURL,
                    trainingAccuracy: trainingAccuracy,
                    validationAccuracy: validationAccuracy,
                    positiveCount: positive.count,
                    negativeCount: negative.count
                )
                results.append(result)

            } catch {
                logger.error("Failed to train '\(tag)': \(error.localizedDescription)")
                // Continue with next tag instead of throwing
                continue
            }
        }

        // Report completion
        await progress?(TrainingProgress(
            phase: .complete,
            currentTag: nil,
            tagsCompleted: tags.count,
            totalTags: tags.count
        ))

        return results
    }

    /// Prepare a DataFrame from tracks for training
    /// - Parameters:
    ///   - tag: The tag being trained
    ///   - tracks: Tracks to include in the DataFrame
    ///   - featureCount: Number of features per track
    /// - Returns: DataFrame with feature columns and label column
    public func prepareDataFrame(
        for tag: String,
        from tracks: [TaggedTrack],
        featureCount: Int
    ) throws -> DataFrame {
        // Create feature columns
        var columns: [String: [Double]] = [:]

        for i in 0..<featureCount {
            columns["f\(i)"] = []
        }

        var labels: [String] = []

        for track in tracks {
            guard let features = track.features, features.count == featureCount else {
                continue
            }

            // Add features to columns
            for (i, value) in features.enumerated() {
                columns["f\(i)"]?.append(Double(value))
            }

            // Add label
            let label = track.tags.contains(tag) ? "positive" : "negative"
            labels.append(label)
        }

        // Build DataFrame
        var dataFrame = DataFrame()

        // Add feature columns in order
        for i in 0..<featureCount {
            let columnName = "f\(i)"
            if let values = columns[columnName] {
                dataFrame.append(column: Column(name: columnName, contents: values))
            }
        }

        // Add label column
        dataFrame.append(column: Column(name: "label", contents: labels))

        return dataFrame
    }

    // MARK: - Private Helpers

    private func splitData(
        _ dataFrame: DataFrame,
        validationSplit: Double,
        seed: Int
    ) -> (training: DataFrame, validation: DataFrame) {
        // Use DataFrame's built-in randomSplit method with seeded generator
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
        let (training, validation) = dataFrame.randomSplit(
            by: 1.0 - validationSplit,
            using: &rng
        )
        return (DataFrame(training), DataFrame(validation))
    }

    private func calculateAccuracy(classifier: MLClassifier, data: DataFrame) -> Double {
        guard data.rows.count > 0 else { return 0.0 }

        do {
            let predictions = try classifier.predictions(from: data)
            let actualLabels = data["label", String.self]

            var correct = 0
            for (index, actual) in actualLabels.enumerated() {
                guard index < predictions.count else { break }
                let predicted = predictions[index] as? String
                if predicted == actual {
                    correct += 1
                }
            }

            return Double(correct) / Double(data.rows.count)
        } catch {
            logger.error("Failed to calculate accuracy: \(error.localizedDescription)")
            return 0.0
        }
    }

    private func sanitizeFileName(_ name: String) -> String {
        // Replace characters that are invalid in file names
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Seeded Random Number Generator

/// A seeded random number generator for reproducible shuffling
public struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        // Simple xorshift algorithm
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
