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

    /// Whether to enable Mixup augmentation
    public let mixupEnabled: Bool

    /// Alpha parameter for Mixup Beta distribution (higher = more mixing)
    public let mixupAlpha: Float

    /// Fraction of samples to generate via mixup (0.0 - 1.0)
    public let mixupRatio: Float

    /// Whether to enable label smoothing (reduces overconfidence)
    public let labelSmoothingEnabled: Bool

    /// Label smoothing factor (typically 0.1, range 0.0-1.0)
    /// For binary: [0, 1] becomes [0.05, 0.95] with factor 0.1
    public let labelSmoothingFactor: Float

    /// Whether to enable contrastive loss diagnostic logging
    /// Lower loss = better class separation in the embedding space
    public let contrastiveLearningEnabled: Bool

    /// MLBoostedTreeClassifier max depth
    public let treeMaxDepth: Int

    /// MLBoostedTreeClassifier iterations
    public let treeIterations: Int

    /// MLBoostedTreeClassifier step size (learning rate)
    public let treeStepSize: Double

    public init(
        validationSplit: Double = 0.2,
        minSamplesPerTag: Int = 50,
        maxNegativeRatio: Double = 1.5,
        randomSeed: Int = 42,
        mixupEnabled: Bool = true,
        mixupAlpha: Float = 0.4,
        mixupRatio: Float = 0.3,
        labelSmoothingEnabled: Bool = true,
        labelSmoothingFactor: Float = 0.1,
        contrastiveLearningEnabled: Bool = true,
        treeMaxDepth: Int = 6,
        treeIterations: Int = 100,
        treeStepSize: Double = 0.3
    ) {
        self.validationSplit = validationSplit
        self.minSamplesPerTag = minSamplesPerTag
        self.maxNegativeRatio = maxNegativeRatio
        self.randomSeed = randomSeed
        self.mixupEnabled = mixupEnabled
        self.mixupAlpha = mixupAlpha
        self.mixupRatio = mixupRatio
        self.labelSmoothingEnabled = labelSmoothingEnabled
        self.labelSmoothingFactor = labelSmoothingFactor
        self.contrastiveLearningEnabled = contrastiveLearningEnabled
        self.treeMaxDepth = treeMaxDepth
        self.treeIterations = treeIterations
        self.treeStepSize = treeStepSize
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

/// A tag that produced no viable training set (BinaryTrainingDataGenerator returned nil)
public struct SkippedTrainingTag: Sendable {
    public enum Reason: Sendable, Equatable {
        /// Fewer positive examples than the configured minimum
        case insufficientPositives(found: Int, required: Int)
        /// Enough positives, but no trusted negatives remained after
        /// category-complete filtering excluded the unknowns
        case noTrustedNegatives

        public var description: String {
            switch self {
            case .insufficientPositives(let found, let required):
                return "\(found) positive samples, \(required) required"
            case .noTrustedNegatives:
                return "No trusted negatives in category (all candidates unknown)"
            }
        }
    }

    public let tag: String
    public let reason: Reason

    public init(tag: String, reason: Reason) {
        self.tag = tag
        self.reason = reason
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

    /// Current item being processed (e.g., "house.mlmodel" or "track_01.mp3")
    public let currentItem: String?

    /// Validation accuracy for the current/last trained tag
    public let accuracy: Double?

    /// Optional status message
    public let message: String?

    public init(
        phase: Phase,
        currentTag: String? = nil,
        tagsCompleted: Int = 0,
        totalTags: Int = 0,
        currentItem: String? = nil,
        accuracy: Double? = nil,
        message: String? = nil
    ) {
        self.phase = phase
        self.currentTag = currentTag
        self.tagsCompleted = tagsCompleted
        self.totalTags = totalTags
        self.currentItem = currentItem
        self.accuracy = accuracy
        self.message = message
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
    ///   - categorizedTags: Tags organized by top-level category (Genre, Timing,
    ///     Mood, Descriptive). Enables category-complete negative filtering:
    ///     tracks with no tags in a tag's category are excluded as unknown rather
    ///     than used as negatives. Empty dictionary disables filtering.
    ///   - progress: Optional progress callback
    /// - Returns: Array of training results for successfully trained models
    public func trainModels(
        from tracks: [TaggedTrack],
        tags: [String],
        outputDirectory: URL,
        config: TrainingConfig = TrainingConfig(),
        categorizedTags: [String: Set<String>] = [:],
        progress: ((TrainingProgress) async -> Void)? = nil
    ) async throws -> [TrainingResult] {
        try await trainModelsWithReport(
            from: tracks,
            tags: tags,
            outputDirectory: outputDirectory,
            config: config,
            categorizedTags: categorizedTags,
            progress: progress
        ).results
    }

    /// Train binary classifiers and also report tags that produced no viable
    /// training set, so callers can surface them instead of silently skipping.
    /// See trainModels(from:tags:outputDirectory:config:categorizedTags:progress:)
    /// for parameter details.
    public func trainModelsWithReport(
        from tracks: [TaggedTrack],
        tags: [String],
        outputDirectory: URL,
        config: TrainingConfig = TrainingConfig(),
        categorizedTags: [String: Set<String>] = [:],
        progress: ((TrainingProgress) async -> Void)? = nil
    ) async throws -> (results: [TrainingResult], skippedTags: [SkippedTrainingTag]) {
        // Build tag -> category lookup (lowercased, matching coordinator metadata grouping)
        var tagToCategory: [String: String] = [:]
        for (category, categoryTags) in categorizedTags {
            for categoryTag in categoryTags {
                tagToCategory[categoryTag.lowercased()] = category
            }
        }

        // Filter tracks that have features (using safe unwrapping)
        let tracksWithFeatures = tracks.compactMap { track -> TaggedTrack? in
            guard let features = track.features, !features.isEmpty else { return nil }
            return track
        }

        guard let firstTrack = tracksWithFeatures.first,
              let features = firstTrack.features else {
            throw TrainerError.noFeaturesAvailable
        }

        // Determine feature count from first track (now safe)
        let featureCount = features.count

        // Create output directory if needed
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var results: [TrainingResult] = []
        var skippedTags: [SkippedTrainingTag] = []

        for (index, tag) in tags.enumerated() {
            // Report preparing phase
            await progress?(TrainingProgress(
                phase: .preparing,
                currentTag: tag,
                tagsCompleted: index,
                totalTags: tags.count
            ))

            // Generate balanced training data using current config,
            // with category-complete negative filtering when the tag's
            // category is known
            let generator = BinaryTrainingDataGenerator(
                minPositiveExamples: config.minSamplesPerTag,
                maxNegativeRatio: config.maxNegativeRatio
            )
            let category = tagToCategory[tag.lowercased()]
            guard let trainingData = generator.generateTrainingData(
                for: tag,
                category: category,
                from: tracksWithFeatures
            ) else {
                let positiveCount = tracksWithFeatures.filter { $0.tags.contains(tag) }.count
                let reason: SkippedTrainingTag.Reason = positiveCount < config.minSamplesPerTag
                    ? .insufficientPositives(found: positiveCount, required: config.minSamplesPerTag)
                    : .noTrustedNegatives
                skippedTags.append(SkippedTrainingTag(tag: tag, reason: reason))
                logger.info("Skipping tag '\(tag)': \(reason.description)")
                continue
            }
            let positive = trainingData.positive
            let negative = trainingData.negative

            logger.info("\(tag): \(positive.count) positive / \(negative.count) trusted negative / \(trainingData.excludedCount) excluded-unknown")

            // Log contrastive loss diagnostic before training
            let allSamples: [(features: [Float], label: String)] =
                positive.compactMap { track in
                    guard let features = track.features else { return nil }
                    return (features: features, label: "positive")
                } +
                negative.compactMap { track in
                    guard let features = track.features else { return nil }
                    return (features: features, label: "negative")
                }
            logContrastiveLoss(samples: allSamples, tag: tag, config: config)

            // Apply mixup augmentation if enabled
            var samplesForTraining = allSamples
            if config.mixupEnabled {
                let augmented = applyMixupAugmentation(to: allSamples, config: config)
                samplesForTraining = augmented.map { ($0.features, $0.label) }
                logger.info("Mixup: \(allSamples.count) → \(samplesForTraining.count) samples")
            }

            // Report training phase
            await progress?(TrainingProgress(
                phase: .training,
                currentTag: tag,
                tagsCompleted: index,
                totalTags: tags.count
            ))

            do {
                // Prepare DataFrame from samples (supports mixup augmented data)
                let dataFrame = try prepareDataFrameFromSamples(
                    samplesForTraining,
                    featureCount: featureCount
                )

                // Split data for training and validation
                let (trainingData, validationData) = splitData(
                    dataFrame,
                    validationSplit: config.validationSplit,
                    seed: config.randomSeed
                )

                // Train the classifier using Boosted Tree (handles high-dim features better)
                let classifier = try MLBoostedTreeClassifier(
                    trainingData: trainingData,
                    targetColumn: "label",
                    parameters: MLBoostedTreeClassifier.ModelParameters(
                        maxDepth: config.treeMaxDepth,
                        maxIterations: config.treeIterations,
                        minLossReduction: 0.0,
                        minChildWeight: 1.0,
                        stepSize: config.treeStepSize
                    )
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

        return (results, skippedTags)
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
        var skippedNaN = 0
        var skippedDimension = 0

        for track in tracks {
            guard let features = track.features, features.count == featureCount else {
                skippedDimension += 1
                continue
            }

            // Skip tracks with NaN or Inf values (CreateML will reject them)
            let hasInvalidValue = features.contains { !$0.isFinite }
            if hasInvalidValue {
                skippedNaN += 1
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

        if skippedDimension > 0 {
            logger.warning("Skipped \(skippedDimension) tracks with wrong feature dimension")
        }
        if skippedNaN > 0 {
            logger.warning("Skipped \(skippedNaN) tracks with NaN/Inf features")
        }

        // NOTE: Z-score normalization removed for train/inference parity
        // Training and inference must use the same feature distribution.
        // EffNet/CLAP embeddings are already well-scaled, and CreateML's
        // BoostedTreeClassifier handles feature scaling internally.
        //
        // Previously this code normalized training data but inference used
        // raw embeddings, causing a distribution mismatch that degraded accuracy.

        // Keep the logging for zero-variance features (useful diagnostic)
        var zeroVarianceCount = 0
        for i in 0..<featureCount {
            let columnName = "f\(i)"
            guard let values = columns[columnName], !values.isEmpty else { continue }

            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)

            if variance < 1e-10 {
                zeroVarianceCount += 1
            }
        }
        if zeroVarianceCount > 0 {
            logger.info("Feature stats: \(zeroVarianceCount)/\(featureCount) zero-variance features")
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

        logger.info("DataFrame prepared: \(dataFrame.rows.count) rows, \(featureCount) features")

        return dataFrame
    }

    /// Prepare a DataFrame from feature samples (used after mixup augmentation)
    /// - Parameters:
    ///   - samples: Array of (features, label) tuples
    ///   - featureCount: Number of features per sample
    /// - Returns: DataFrame with feature columns and label column
    private func prepareDataFrameFromSamples(
        _ samples: [(features: [Float], label: String)],
        featureCount: Int
    ) throws -> DataFrame {
        // Create feature columns
        var columns: [String: [Double]] = [:]

        for i in 0..<featureCount {
            columns["f\(i)"] = []
        }

        var labels: [String] = []
        var skippedNaN = 0
        var skippedDimension = 0

        for sample in samples {
            let features = sample.features

            guard features.count == featureCount else {
                skippedDimension += 1
                continue
            }

            // Skip samples with NaN or Inf values (CreateML will reject them)
            let hasInvalidValue = features.contains { !$0.isFinite }
            if hasInvalidValue {
                skippedNaN += 1
                continue
            }

            // Add features to columns
            for (i, value) in features.enumerated() {
                columns["f\(i)"]?.append(Double(value))
            }

            // Add label
            labels.append(sample.label)
        }

        if skippedDimension > 0 {
            logger.warning("Skipped \(skippedDimension) samples with wrong feature dimension")
        }
        if skippedNaN > 0 {
            logger.warning("Skipped \(skippedNaN) samples with NaN/Inf features")
        }

        // NOTE: Z-score normalization removed for train/inference parity
        // Training and inference must use the same feature distribution.
        // EffNet/CLAP embeddings are already well-scaled, and CreateML's
        // BoostedTreeClassifier handles feature scaling internally.
        //
        // Previously this code normalized training data but inference used
        // raw embeddings, causing a distribution mismatch that degraded accuracy.

        // Keep the logging for zero-variance features (useful diagnostic)
        var zeroVarianceCount = 0
        for i in 0..<featureCount {
            let columnName = "f\(i)"
            guard let values = columns[columnName], !values.isEmpty else { continue }

            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)

            if variance < 1e-10 {
                zeroVarianceCount += 1
            }
        }
        if zeroVarianceCount > 0 {
            logger.info("Feature stats: \(zeroVarianceCount)/\(featureCount) zero-variance features")
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

        logger.info("DataFrame prepared from samples: \(dataFrame.rows.count) rows, \(featureCount) features")

        return dataFrame
    }

    // MARK: - Multi-Class Training

    /// Train a multi-class classifier for a tag group
    /// - Parameters:
    ///   - data: Multi-class training data from MultiClassTrainingDataGenerator
    ///   - outputDirectory: Directory to save trained model
    ///   - validationSplit: Fraction of data to use for validation (0.0 - 1.0)
    ///   - useLabelSmoothing: Whether to apply label smoothing (helps prevent overconfidence)
    ///   - smoothingFactor: Label smoothing factor (0.0 - 1.0, typically 0.1)
    ///   - config: Training configuration (uses defaults if not provided)
    /// - Returns: Training result with accuracy metrics and model URL
    public func trainMultiClassModel(
        data: MultiClassTrainingDataGenerator.MultiClassTrainingData,
        outputDirectory: URL,
        validationSplit: Double = 0.2,
        useLabelSmoothing: Bool = true,
        smoothingFactor: Float = 0.1,
        config: TrainingConfig = TrainingConfig()
    ) async throws -> MultiClassTrainingResult {
        let groupName = data.groupName
        let classes = data.classes

        logger.info("Training multi-class model for '\(groupName)' with \(classes.count) classes")

        // Validate we have enough classes
        guard classes.count >= 2 else {
            throw TrainerError.trainingFailed(
                tag: groupName,
                reason: "Need at least 2 classes for multi-class training"
            )
        }

        // Prepare DataFrame from samples
        let dataFrame = try prepareMultiClassDataFrame(from: data, useLabelSmoothing: useLabelSmoothing, smoothingFactor: smoothingFactor)

        guard dataFrame.rows.count > 0 else {
            throw TrainerError.noFeaturesAvailable
        }

        // Split data for training and validation
        let (trainingData, validationData) = splitData(
            dataFrame,
            validationSplit: validationSplit,
            seed: 42  // Fixed seed for reproducibility
        )

        logger.info("Split data: \(trainingData.rows.count) training, \(validationData.rows.count) validation")

        // Train the classifier
        let classifier = try MLBoostedTreeClassifier(
            trainingData: trainingData,
            targetColumn: "label",
            parameters: MLBoostedTreeClassifier.ModelParameters(
                maxDepth: config.treeMaxDepth,
                maxIterations: config.treeIterations,
                minLossReduction: 0.0,
                minChildWeight: 1.0,
                stepSize: config.treeStepSize
            )
        )

        // Evaluate on validation set
        let (accuracy, perClassAccuracy, confusionMatrix) = evaluateMultiClassClassifier(
            classifier: classifier,
            data: validationData,
            classes: classes
        )

        logger.info("'\(groupName)' - Validation accuracy: \(accuracy)")
        for (className, classAccuracy) in perClassAccuracy.sorted(by: { $0.key < $1.key }) {
            logger.info("  \(className): \(classAccuracy)")
        }

        // Create output directory if needed
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // Save the model
        let sanitizedName = sanitizeFileName(groupName)
        let modelURL = outputDirectory.appendingPathComponent("\(sanitizedName)_multiclass.mlmodel")

        do {
            try classifier.write(to: modelURL, metadata: nil)
        } catch {
            throw TrainerError.saveFailed(tag: groupName, reason: error.localizedDescription)
        }

        return MultiClassTrainingResult(
            groupName: groupName,
            classes: classes,
            accuracy: accuracy,
            perClassAccuracy: perClassAccuracy,
            confusionMatrix: confusionMatrix,
            modelURL: modelURL
        )
    }

    /// Prepare DataFrame for multi-class training
    private func prepareMultiClassDataFrame(
        from data: MultiClassTrainingDataGenerator.MultiClassTrainingData,
        useLabelSmoothing: Bool,
        smoothingFactor: Float
    ) throws -> DataFrame {
        let samples = data.samples
        guard !samples.isEmpty else {
            throw TrainerError.noFeaturesAvailable
        }

        // Determine feature count from first sample
        let featureCount = samples[0].features.count

        // Create feature columns
        var columns: [String: [Double]] = [:]
        for i in 0..<featureCount {
            columns["f\(i)"] = []
        }

        var labels: [String] = []
        var skippedNaN = 0
        var skippedDimension = 0

        for sample in samples {
            let features = sample.features

            guard features.count == featureCount else {
                skippedDimension += 1
                continue
            }

            // Skip samples with NaN or Inf values
            let hasInvalidValue = features.contains { !$0.isFinite }
            if hasInvalidValue {
                skippedNaN += 1
                continue
            }

            // Add features to columns
            for (i, value) in features.enumerated() {
                columns["f\(i)"]?.append(Double(value))
            }

            // Add class label
            labels.append(sample.className)
        }

        if skippedDimension > 0 {
            logger.warning("Skipped \(skippedDimension) samples with wrong feature dimension")
        }
        if skippedNaN > 0 {
            logger.warning("Skipped \(skippedNaN) samples with NaN/Inf features")
        }

        // NOTE: Z-score normalization removed for train/inference parity
        // Training and inference must use the same feature distribution.
        // EffNet/CLAP embeddings are already well-scaled, and CreateML's
        // BoostedTreeClassifier handles feature scaling internally.
        //
        // Previously this code normalized training data but inference used
        // raw embeddings, causing a distribution mismatch that degraded accuracy.

        // Keep the logging for zero-variance features (useful diagnostic)
        var zeroVarianceCount = 0
        for i in 0..<featureCount {
            let columnName = "f\(i)"
            guard let values = columns[columnName], !values.isEmpty else { continue }

            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)

            if variance < 1e-10 {
                zeroVarianceCount += 1
            }
        }
        if zeroVarianceCount > 0 {
            logger.info("Feature stats: \(zeroVarianceCount)/\(featureCount) zero-variance features")
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

        logger.info("Multi-class DataFrame prepared: \(dataFrame.rows.count) rows, \(featureCount) features, \(data.classes.count) classes")

        return dataFrame
    }

    /// Evaluate a multi-class classifier and return metrics
    private func evaluateMultiClassClassifier(
        classifier: MLBoostedTreeClassifier,
        data: DataFrame,
        classes: [String]
    ) -> (accuracy: Double, perClassAccuracy: [String: Double], confusionMatrix: [[Int]]) {
        guard data.rows.count > 0 else {
            let emptyMatrix = Array(repeating: Array(repeating: 0, count: classes.count), count: classes.count)
            return (0.0, [:], emptyMatrix)
        }

        // Initialize confusion matrix (rows = actual, columns = predicted)
        let numClasses = classes.count
        var confusionMatrix = Array(repeating: Array(repeating: 0, count: numClasses), count: numClasses)

        // Create class-to-index mapping
        var classToIndex: [String: Int] = [:]
        for (index, className) in classes.enumerated() {
            classToIndex[className] = index
        }

        // Track per-class correct and total
        var classCorrect: [String: Int] = [:]
        var classTotal: [String: Int] = [:]
        for className in classes {
            classCorrect[className] = 0
            classTotal[className] = 0
        }

        do {
            let predictions = try classifier.predictions(from: data)
            let actualLabels = data["label", String.self]

            for (index, actual) in actualLabels.enumerated() {
                guard let actualClass = actual,
                      index < predictions.count,
                      let predicted = predictions[index] as? String,
                      let actualIdx = classToIndex[actualClass],
                      let predictedIdx = classToIndex[predicted] else {
                    continue
                }

                // Update confusion matrix
                confusionMatrix[actualIdx][predictedIdx] += 1

                // Update per-class counts
                classTotal[actualClass, default: 0] += 1
                if predicted == actualClass {
                    classCorrect[actualClass, default: 0] += 1
                }
            }
        } catch {
            logger.error("Failed to get predictions: \(error.localizedDescription)")
            let emptyMatrix = Array(repeating: Array(repeating: 0, count: classes.count), count: classes.count)
            return (0.0, [:], emptyMatrix)
        }

        // Calculate overall accuracy
        var totalCorrect = 0
        var totalSamples = 0
        for i in 0..<numClasses {
            totalCorrect += confusionMatrix[i][i]
            totalSamples += confusionMatrix[i].reduce(0, +)
        }
        let accuracy = totalSamples > 0 ? Double(totalCorrect) / Double(totalSamples) : 0.0

        // Calculate per-class accuracy
        var perClassAccuracy: [String: Double] = [:]
        for className in classes {
            let correct = classCorrect[className] ?? 0
            let total = classTotal[className] ?? 0
            perClassAccuracy[className] = total > 0 ? Double(correct) / Double(total) : 0.0
        }

        return (accuracy, perClassAccuracy, confusionMatrix)
    }

    // MARK: - Label Smoothing

    /// Apply label smoothing to convert hard labels to soft probability distributions
    /// - Parameters:
    ///   - hardLabel: The index of the true class (0 or 1 for binary)
    ///   - numClasses: Total number of classes (2 for binary classification)
    ///   - smoothingFactor: How much probability mass to redistribute (typically 0.1)
    /// - Returns: Soft label distribution where hard label gets (1-smoothing) and rest is distributed
    /// - Note: CreateML MLBoostedTreeClassifier uses hard labels internally, so these soft labels
    ///         are used for confidence calibration during inference (see ConfidenceCalibrator).
    ///         For full soft label training, a custom gradient boosting or neural network
    ///         implementation would be required.
    public func applySoftLabels(
        hardLabel: Int,
        numClasses: Int,
        smoothingFactor: Float
    ) -> [Float] {
        // Distribute smoothingFactor equally among all classes
        // Then add (1 - smoothingFactor) to the true class
        // For binary with factor 0.1: [0, 1] becomes [0.05, 0.95]
        var softLabels = [Float](repeating: smoothingFactor / Float(numClasses), count: numClasses)
        softLabels[hardLabel] = 1.0 - smoothingFactor + smoothingFactor / Float(numClasses)
        return softLabels
    }

    // MARK: - Contrastive Loss Diagnostic

    /// Log contrastive loss as a diagnostic metric before training
    /// Lower loss indicates better class separation in the embedding space
    /// - Parameters:
    ///   - samples: Training samples with features and labels
    ///   - tag: The tag being trained (for logging purposes)
    ///   - config: Training configuration
    private func logContrastiveLoss(
        samples: [(features: [Float], label: String)],
        tag: String,
        config: TrainingConfig
    ) {
        guard config.contrastiveLearningEnabled else { return }

        let embeddings = samples.map { $0.features }
        let labels = samples.map { $0.label }

        let loss = ContrastiveLoss.compute(
            embeddings: embeddings,
            labels: labels,
            temperature: 0.07
        )

        logger.info("Contrastive loss for '\(tag)': \(String(format: "%.4f", loss))")

        // Lower loss = better class separation
        // Use this as a diagnostic: if loss is high, the tag may need more training data
        // or the embeddings don't capture the concept well
        if loss > 5.0 {
            logger.warning("High contrastive loss for '\(tag)' suggests poor feature separation - consider more training data")
        } else if loss < 1.0 {
            logger.info("Low contrastive loss for '\(tag)' indicates good feature separation")
        }
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

    private func calculateAccuracy(classifier: MLBoostedTreeClassifier, data: DataFrame) -> Double {
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

    // MARK: - Mixup Augmentation

    /// Apply Mixup augmentation to training samples
    /// - Parameters:
    ///   - samples: Original training samples with features and labels
    ///   - config: Training configuration with mixup parameters
    /// - Returns: Augmented samples including original and mixed samples
    /// - Note: MLBoostedTreeClassifier doesn't support soft labels, so we use the dominant label
    ///         as the hard label but preserve soft labels for potential future use
    private func applyMixupAugmentation(
        to samples: [(features: [Float], label: String)],
        config: TrainingConfig
    ) -> [(features: [Float], label: String, softLabel: [String: Float]?)] {
        guard config.mixupEnabled else {
            return samples.map { ($0.features, $0.label, nil) }
        }

        var augmented: [(features: [Float], label: String, softLabel: [String: Float]?)] = []
        let mixupCount = Int(Float(samples.count) * config.mixupRatio)

        // Keep original samples
        for sample in samples {
            augmented.append((sample.features, sample.label, nil))
        }

        // Add mixup samples
        for _ in 0..<mixupCount {
            let idx1 = Int.random(in: 0..<samples.count)
            let idx2 = Int.random(in: 0..<samples.count)
            guard idx1 != idx2 else { continue }

            let result = AudioAugmenter.mixup(
                features1: samples[idx1].features,
                features2: samples[idx2].features,
                label1: samples[idx1].label,
                label2: samples[idx2].label,
                alpha: config.mixupAlpha
            )

            // Use dominant label for hard label (required for MLBoostedTreeClassifier)
            let dominantLabel = result.softLabels.max(by: { $0.value < $1.value })?.key ?? samples[idx1].label
            augmented.append((result.features, dominantLabel, result.softLabels))
        }

        logger.info("Mixup augmentation: \(samples.count) original + \(augmented.count - samples.count) mixed = \(augmented.count) total samples")

        return augmented
    }
}

// MARK: - Multi-Class Training

/// Result of training a multi-class classifier
public struct MultiClassTrainingResult: Sendable {
    /// Name of the tag group (e.g., "Genre", "Energy")
    public let groupName: String

    /// The classes that were trained
    public let classes: [String]

    /// Overall accuracy on validation set
    public let accuracy: Double

    /// Per-class accuracy breakdown
    public let perClassAccuracy: [String: Double]

    /// Confusion matrix for analysis (rows = actual, columns = predicted)
    public let confusionMatrix: [[Int]]

    /// URL where the model was saved
    public let modelURL: URL

    public init(
        groupName: String,
        classes: [String],
        accuracy: Double,
        perClassAccuracy: [String: Double],
        confusionMatrix: [[Int]],
        modelURL: URL
    ) {
        self.groupName = groupName
        self.classes = classes
        self.accuracy = accuracy
        self.perClassAccuracy = perClassAccuracy
        self.confusionMatrix = confusionMatrix
        self.modelURL = modelURL
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
