import Foundation
import CreateML
import TabularData

/// Configuration for an experiment
public struct ExperimentConfiguration: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let sampleSize: SampleSize
    public let extractors: [String]
    public let folds: Int
    public let tags: [String]?  // nil = all viable tags
    public let seed: UInt64

    public init(
        name: String,
        sampleSize: SampleSize,
        extractors: [String],
        folds: Int = 5,
        tags: [String]? = nil,
        seed: UInt64 = 42
    ) {
        self.name = name
        self.sampleSize = sampleSize
        self.extractors = extractors
        self.folds = folds
        self.tags = tags
        self.seed = seed
    }
}

/// Result for a single tag's experiment
public struct TagExperimentResult: Codable, Sendable, Identifiable {
    public var id: String { tag }
    public let tag: String
    public let metrics: ValidationMetrics
    public let optimalThreshold: Float
    public let sampleCount: Int
    public let positiveCount: Int
    public let negativeCount: Int
    public let perFoldMetrics: [ValidationMetrics]

    public init(
        tag: String,
        metrics: ValidationMetrics,
        optimalThreshold: Float,
        sampleCount: Int,
        positiveCount: Int = 0,
        negativeCount: Int = 0,
        perFoldMetrics: [ValidationMetrics] = []
    ) {
        self.tag = tag
        self.metrics = metrics
        self.optimalThreshold = optimalThreshold
        self.sampleCount = sampleCount
        self.positiveCount = positiveCount
        self.negativeCount = negativeCount
        self.perFoldMetrics = perFoldMetrics
    }

    /// Whether this tag meets viability criteria (50+ positive samples AND F1 >= 0.6)
    public var isViable: Bool {
        positiveCount >= 50 && metrics.f1Score >= 0.6
    }
}

/// Complete experiment result
public struct ExperimentResult: Codable, Sendable, Identifiable {
    public var id: String { configuration.name }
    public let configuration: ExperimentConfiguration
    public let tagResults: [TagExperimentResult]
    public let duration: TimeInterval
    public let tracksUsed: Int
    public let startedAt: Date
    public let completedAt: Date

    public init(
        configuration: ExperimentConfiguration,
        tagResults: [TagExperimentResult],
        duration: TimeInterval,
        tracksUsed: Int,
        startedAt: Date = Date(),
        completedAt: Date = Date()
    ) {
        self.configuration = configuration
        self.tagResults = tagResults
        self.duration = duration
        self.tracksUsed = tracksUsed
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    /// Average accuracy across all tags
    public var averageAccuracy: Double {
        guard !tagResults.isEmpty else { return 0 }
        return tagResults.map(\.metrics.accuracy).reduce(0, +) / Double(tagResults.count)
    }

    /// Average F1 score across all tags
    public var averageF1: Double {
        guard !tagResults.isEmpty else { return 0 }
        return tagResults.map(\.metrics.f1Score).reduce(0, +) / Double(tagResults.count)
    }

    /// Tags that meet viability criteria
    public var viableTags: [TagExperimentResult] {
        tagResults.filter(\.isViable)
    }

    /// Tags that don't meet viability criteria
    public var nonViableTags: [TagExperimentResult] {
        tagResults.filter { !$0.isViable }
    }
}

/// Progress during experiment
public struct ExperimentProgress: Sendable {
    public enum Phase: Sendable {
        case collecting
        case extractingFeatures
        case training(tag: String, fold: Int)
        case evaluating(tag: String)
        case complete
    }

    public let phase: Phase
    public let overallProgress: Double  // 0.0 to 1.0
    public let currentTag: String?
    public let currentFold: Int?
    public let tagsCompleted: Int
    public let totalTags: Int

    public init(
        phase: Phase,
        overallProgress: Double,
        currentTag: String? = nil,
        currentFold: Int? = nil,
        tagsCompleted: Int = 0,
        totalTags: Int = 0
    ) {
        self.phase = phase
        self.overallProgress = overallProgress
        self.currentTag = currentTag
        self.currentFold = currentFold
        self.tagsCompleted = tagsCompleted
        self.totalTags = totalTags
    }
}

/// Runs experiments with cross-validation
public actor ExperimentRunner {
    private let dataCollector: TrainingDataCollector
    private let dataGenerator: BinaryTrainingDataGenerator
    private let sampler: StratifiedSampler

    public init(
        dataCollector: TrainingDataCollector = TrainingDataCollector(),
        seed: UInt64 = 42
    ) {
        self.dataCollector = dataCollector
        self.dataGenerator = BinaryTrainingDataGenerator()
        self.sampler = StratifiedSampler(seed: seed)
    }

    /// Run a complete experiment
    public func runExperiment(
        directories: [URL],
        configuration: ExperimentConfiguration,
        progress: (@Sendable (ExperimentProgress) async -> Void)? = nil
    ) async throws -> ExperimentResult {
        let startTime = Date()

        // Phase 1: Collect tracks
        await progress?(ExperimentProgress(phase: .collecting, overallProgress: 0.0))
        let collectionResult = await dataCollector.collectTrainingData(from: directories)
        var tracks = collectionResult.tracks

        // Phase 2: Extract features
        await progress?(ExperimentProgress(phase: .extractingFeatures, overallProgress: 0.1))
        tracks = await dataCollector.extractFeatures(for: tracks)

        // Filter to tracks with features
        let tracksWithFeatures = tracks.filter { track in
            guard let features = track.features else { return false }
            return !features.isEmpty
        }

        // Sample if needed
        let sampledTracks = sampler.sample(
            from: tracksWithFeatures,
            size: configuration.sampleSize,
            stratifyBy: \.primaryTag
        )

        // Determine tags to test
        let viableTagCounts = dataGenerator.viableTags(from: sampledTracks)
        let tagsToTest: [String]
        if let specifiedTags = configuration.tags {
            tagsToTest = specifiedTags.filter { viableTagCounts[$0] != nil }
        } else {
            tagsToTest = Array(viableTagCounts.keys).sorted()
        }

        // Phase 3: Run cross-validation for each tag
        // Derive tag -> category from the collected tracks (a tag's category is
        // whichever tagsByCategory key contains it), so experiments use the same
        // category-complete negative sampling as production training.
        let tagToCategory = Self.deriveTagCategories(from: sampledTracks)
        var tagResults: [TagExperimentResult] = []
        let validator = CrossValidator(folds: configuration.folds, seed: configuration.seed)

        for (index, tag) in tagsToTest.enumerated() {
            let tagProgress = Double(index) / Double(tagsToTest.count)
            await progress?(ExperimentProgress(
                phase: .training(tag: tag, fold: 0),
                overallProgress: 0.2 + tagProgress * 0.7,
                currentTag: tag,
                tagsCompleted: index,
                totalTags: tagsToTest.count
            ))

            let result = await evaluateTag(
                tag,
                category: tagToCategory[tag.lowercased()],
                tracks: sampledTracks,
                validator: validator
            )
            tagResults.append(result)
        }

        await progress?(ExperimentProgress(phase: .complete, overallProgress: 1.0))

        let endTime = Date()
        return ExperimentResult(
            configuration: configuration,
            tagResults: tagResults,
            duration: endTime.timeIntervalSince(startTime),
            tracksUsed: sampledTracks.count,
            startedAt: startTime,
            completedAt: endTime
        )
    }

    /// Build a tag -> category lookup (lowercased keys, matching ModelTrainer)
    /// from the per-track category breakdown. Descriptive tags are folded into
    /// their sub-category (BassType, Rhythm, Vibes, ...) via
    /// DescriptiveTagMapping.effectiveCategory so category-complete negative
    /// filtering bites at sub-category granularity — matches ModelTrainer and
    /// the post-collector sub-category-keyed per-track tagsByCategory.
    static func deriveTagCategories(from tracks: [TaggedTrack]) -> [String: String] {
        var tagToCategory: [String: String] = [:]
        for track in tracks {
            // Keep the alphabetically-first category on collision so duplicate tag
            // names resolve deterministically, not by dictionary iteration order.
            for category in track.tagsByCategory.keys.sorted() {
                for tag in track.tagsByCategory[category] ?? [] {
                    let key = tag.lowercased()
                    let resolved = DescriptiveTagMapping.effectiveCategory(
                        for: tag, topLevel: category
                    )
                    if let existing = tagToCategory[key], existing <= resolved {
                        continue
                    }
                    tagToCategory[key] = resolved
                }
            }
        }
        return tagToCategory
    }

    /// Evaluate a single tag with cross-validation
    private func evaluateTag(
        _ tag: String,
        category: String?,
        tracks: [TaggedTrack],
        validator: CrossValidator
    ) async -> TagExperimentResult {
        // Get positive/negative samples with category-complete negative
        // filtering when the tag's category is known (nil category falls back
        // to legacy all-non-positives-are-negatives behavior)
        guard let trainingData = dataGenerator.generateTrainingData(for: tag, category: category, from: tracks) else {
            return TagExperimentResult(
                tag: tag,
                metrics: ValidationMetrics(
                    accuracy: 0, precision: 0, recall: 0, f1Score: 0,
                    truePositives: 0, falsePositives: 0, trueNegatives: 0, falseNegatives: 0
                ),
                optimalThreshold: 0.5,
                sampleCount: 0,
                positiveCount: 0,
                negativeCount: 0
            )
        }
        let positive = trainingData.positive
        let negative = trainingData.negative

        // Combine and label
        let combined = positive + negative
        let folds = validator.createFolds(from: combined)

        // Evaluate each fold
        var foldMetrics: [ValidationMetrics] = []

        for fold in folds {
            let metrics = evaluateFold(fold: fold, tag: tag)
            foldMetrics.append(metrics)
        }

        let averageMetrics = ValidationMetrics.average(foldMetrics)

        return TagExperimentResult(
            tag: tag,
            metrics: averageMetrics,
            optimalThreshold: 0.5,  // Simplified - real implementation would optimize
            sampleCount: positive.count + negative.count,
            positiveCount: positive.count,
            negativeCount: negative.count,
            perFoldMetrics: foldMetrics
        )
    }

    /// Evaluate a single fold by training a CreateML classifier
    private func evaluateFold(
        fold: CrossValidator.Fold,
        tag: String
    ) -> ValidationMetrics {
        // Build training DataFrame
        guard let featureCount = fold.train.first?.features?.count, featureCount > 0 else {
            return ValidationMetrics.empty
        }

        // Create column data for training
        var featureColumns: [[Double]] = Array(repeating: [], count: featureCount)
        var labels: [String] = []

        for track in fold.train {
            guard let features = track.features, features.count == featureCount else { continue }
            for (i, value) in features.enumerated() {
                featureColumns[i].append(Double(value))
            }
            labels.append(track.tags.contains(tag) ? "positive" : "negative")
        }

        // Build DataFrame
        var trainDF = DataFrame()
        for i in 0..<featureCount {
            trainDF.append(column: Column(name: "f\(i)", contents: featureColumns[i]))
        }
        trainDF.append(column: Column(name: "label", contents: labels))

        // Train classifier
        let classifier: MLClassifier
        do {
            classifier = try MLClassifier(trainingData: trainDF, targetColumn: "label")
        } catch {
            // Training failed - return empty metrics
            return ValidationMetrics.empty
        }

        // Evaluate on test set
        var predictions: [(predicted: Bool, actual: Bool)] = []

        for track in fold.test {
            guard let features = track.features, features.count == featureCount else { continue }

            // Build single-row DataFrame for prediction
            var testDF = DataFrame()
            for (i, value) in features.enumerated() {
                testDF.append(column: Column(name: "f\(i)", contents: [Double(value)]))
            }

            let actual = track.tags.contains(tag)

            // Get prediction
            do {
                let predictionColumn = try classifier.predictions(from: testDF)
                if let prediction = predictionColumn.first as? String {
                    let predicted = prediction == "positive"
                    predictions.append((predicted: predicted, actual: actual))
                }
            } catch {
                // Prediction failed for this track - skip
                continue
            }
        }

        return ValidationMetrics.calculate(from: predictions)
    }
}

extension ValidationMetrics {
    static var empty: ValidationMetrics {
        ValidationMetrics(
            accuracy: 0, precision: 0, recall: 0, f1Score: 0,
            truePositives: 0, falsePositives: 0, trueNegatives: 0, falseNegatives: 0
        )
    }
}

// Extension for primaryTag
public extension TaggedTrack {
    var primaryTag: String {
        tags.first ?? "Unknown"
    }
}
