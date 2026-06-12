import AVFoundation
import Foundation
import os.log

/// Errors that can occur during training coordination
public enum CoordinatorError: Error, LocalizedError, Sendable {
    case noDataFound
    case insufficientData(details: String)
    case trainingFailed(reason: String)
    case saveFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .noDataFound:
            return "No training data found in the specified directories"
        case .insufficientData(let details):
            return "Insufficient data for training: \(details)"
        case .trainingFailed(let reason):
            return "Training failed: \(reason)"
        case .saveFailed(let reason):
            return "Failed to save model: \(reason)"
        }
    }
}

/// Orchestrates the full training workflow: collect data, extract features, train models, and package with metadata
public actor TrainingCoordinator {

    // MARK: - Types

    /// Detailed progress information for a phase
    public struct DetailedProgress: Sendable, Equatable {
        public let processed: Int
        public let total: Int
        public let currentFile: String?
        /// All files being processed (for displaying full list with status)
        public let allFiles: [String]

        public var fraction: Double {
            guard total > 0 else { return 0.0 }
            return Double(processed) / Double(total)
        }

        public init(processed: Int = 0, total: Int = 0, currentFile: String? = nil, allFiles: [String] = []) {
            self.processed = processed
            self.total = total
            self.currentFile = currentFile
            self.allFiles = allFiles
        }

        public static let zero = DetailedProgress()
    }

    /// State of the training coordinator
    public enum State: Sendable, Equatable {
        case idle
        case collecting(progress: DetailedProgress)
        case extractingFeatures(progress: DetailedProgress)
        case training(progress: Double, currentTag: String?)
        case packaging
        case complete(modelName: String)
        case failed(error: String)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case (.collecting(let l), .collecting(let r)):
                return l == r
            case (.extractingFeatures(let l), .extractingFeatures(let r)):
                return l == r
            case (.training(let lProgress, let lTag), .training(let rProgress, let rTag)):
                return lProgress == rProgress && lTag == rTag
            case (.packaging, .packaging):
                return true
            case (.complete(let l), .complete(let r)):
                return l == r
            case (.failed(let l), .failed(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    /// Configuration options for training
    public struct TrainingOptions: Sendable {
        /// Name for the trained model
        public let modelName: String

        /// Tags to train (nil means all discovered tags)
        public let selectedTags: Set<String>?

        /// Tags organized by category (Genre, Timing, Mood, Descriptive)
        /// Used to properly categorize tags in model metadata
        public let tagsByCategory: [String: Set<String>]

        /// Mapping of ID3 fields to training categories
        public let tagFieldMapping: TrainingDataCollector.TagFieldMapping

        /// Registry of mutually exclusive tag groups for multi-class classification
        public let tagGroupRegistry: TagGroupRegistry

        /// Training hyperparameters configuration (includes minSamplesPerTag, validationSplit)
        public let configuration: TrainingConfiguration

        public init(
            modelName: String = "CustomModel",
            selectedTags: Set<String>? = nil,
            tagsByCategory: [String: Set<String>] = [:],
            tagFieldMapping: TrainingDataCollector.TagFieldMapping = .default,
            tagGroupRegistry: TagGroupRegistry = .defaultGroups,
            configuration: TrainingConfiguration = .default
        ) {
            self.modelName = modelName
            self.selectedTags = selectedTags
            self.tagsByCategory = tagsByCategory
            self.tagFieldMapping = tagFieldMapping
            self.tagGroupRegistry = tagGroupRegistry
            self.configuration = configuration
        }
    }

    /// Metadata about a trained tag group (multi-class classifier)
    public struct TagGroupInfo: Codable, Sendable {
        /// Name of the tag group (e.g., "BassType", "Vibe")
        public let groupName: String

        /// Classes included in this group
        public let classes: [String]

        /// Overall validation accuracy
        public let accuracy: Double

        /// Per-class accuracy breakdown
        public let perClassAccuracy: [String: Double]

        public init(
            groupName: String,
            classes: [String],
            accuracy: Double,
            perClassAccuracy: [String: Double]
        ) {
            self.groupName = groupName
            self.classes = classes
            self.accuracy = accuracy
            self.perClassAccuracy = perClassAccuracy
        }
    }

    /// Detailed result for a single trained tag
    public struct TagTrainingResult: Sendable {
        public let tag: String
        public let trainingAccuracy: Double
        public let validationAccuracy: Double
        public let positiveCount: Int
        public let negativeCount: Int

        public init(tag: String, trainingAccuracy: Double, validationAccuracy: Double, positiveCount: Int, negativeCount: Int) {
            self.tag = tag
            self.trainingAccuracy = trainingAccuracy
            self.validationAccuracy = validationAccuracy
            self.positiveCount = positiveCount
            self.negativeCount = negativeCount
        }
    }

    /// Reason why a tag was skipped
    public struct SkippedTag: Sendable {
        public let tag: String
        public let reason: SkipReason
        public let sampleCount: Int

        public enum SkipReason: Sendable {
            case insufficientSamples(required: Int)
            case trainingFailed(error: String)
            /// Category-complete filtering left no trusted negatives:
            /// every candidate negative was unknown for the tag's category
            case noTrustedNegatives

            public var description: String {
                switch self {
                case .insufficientSamples(let required):
                    return "Needs \(required)+ samples"
                case .trainingFailed(let error):
                    return "Training failed: \(error)"
                case .noTrustedNegatives:
                    return "No trusted negatives in category"
                }
            }
        }

        public init(tag: String, reason: SkipReason, sampleCount: Int) {
            self.tag = tag
            self.reason = reason
            self.sampleCount = sampleCount
        }
    }

    /// Summary of a training run
    public struct TrainingSummary: Sendable {
        /// Name of the trained model
        public let modelName: String

        /// Detailed results for each trained tag (binary classifiers)
        public let tagResults: [TagTrainingResult]

        /// Results for multi-class tag groups
        public let tagGroupResults: [TagGroupInfo]

        /// Tags that were skipped with reasons
        public let skippedTagDetails: [SkippedTag]

        /// Total number of tracks scanned
        public let totalTracksScanned: Int

        /// Number of tracks used for training (after filtering)
        public let tracksUsedForTraining: Int

        /// Number of tracks skipped due to invalid features (NaN/Inf)
        public let tracksWithInvalidFeatures: Int

        /// Average validation accuracy across all trained models
        public let averageAccuracy: Double

        /// URL where the model was saved
        public let modelURL: URL

        /// Tags that were successfully trained (convenience accessor)
        public var trainedTags: [String] {
            tagResults.map { $0.tag }
        }

        /// Tags that were skipped (convenience accessor)
        public var skippedTags: [String] {
            skippedTagDetails.map { $0.tag }
        }

        /// Total number of tracks (for backwards compatibility)
        public var totalTracks: Int {
            tracksUsedForTraining
        }

        public init(
            modelName: String,
            tagResults: [TagTrainingResult],
            tagGroupResults: [TagGroupInfo] = [],
            skippedTagDetails: [SkippedTag],
            totalTracksScanned: Int,
            tracksUsedForTraining: Int,
            tracksWithInvalidFeatures: Int,
            averageAccuracy: Double,
            modelURL: URL
        ) {
            self.modelName = modelName
            self.tagResults = tagResults
            self.tagGroupResults = tagGroupResults
            self.skippedTagDetails = skippedTagDetails
            self.totalTracksScanned = totalTracksScanned
            self.tracksUsedForTraining = tracksUsedForTraining
            self.tracksWithInvalidFeatures = tracksWithInvalidFeatures
            self.averageAccuracy = averageAccuracy
            self.modelURL = modelURL
        }
    }

    // MARK: - Properties

    private var _state: State = .idle
    private let logger = Logger(subsystem: "com.cratebot.core", category: "TrainingCoordinator")

    private let dataCollector: TrainingDataCollector
    private let modelTrainer: ModelTrainer
    private let modelManager: ModelManager
    private let checkpointManager: CheckpointManager

    /// Current state of the coordinator
    public var state: State {
        _state
    }

    // MARK: - Initialization

    public init(
        dataCollector: TrainingDataCollector = TrainingDataCollector(),
        modelTrainer: ModelTrainer = ModelTrainer(),
        modelManager: ModelManager = ModelManager(),
        checkpointManager: CheckpointManager = CheckpointManager()
    ) {
        self.dataCollector = dataCollector
        self.modelTrainer = modelTrainer
        self.modelManager = modelManager
        self.checkpointManager = checkpointManager
    }

    // MARK: - Public Methods

    /// Run the full training pipeline
    /// - Parameters:
    ///   - directories: Directories to scan for training data
    ///   - options: Training configuration options
    ///   - stateCallback: Optional callback for state updates
    /// - Returns: A summary of the training run
    public func train(
        from directories: [URL],
        options: TrainingOptions = TrainingOptions(),
        stateCallback: (@Sendable (State) async -> Void)? = nil
    ) async throws -> TrainingSummary {
        do {
            // Configure feature augmentation based on training options
            let defaultAug = AudioAugmenter.AugmentationConfig.default
            await dataCollector.setAugmentationConfig(AudioAugmenter.AugmentationConfig(
                featureNoiseEnabled: options.configuration.enableFeatureNoise,
                featureNoiseScale: options.configuration.featureNoisePercent,
                mixupEnabled: options.configuration.enableMixup,
                mixupAlpha: options.configuration.mixupAlpha,
                freqMaskCount: 0,
                freqMaskWidth: defaultAug.freqMaskWidth,
                timeMaskCount: 0,
                timeMaskWidth: defaultAug.timeMaskWidth
            ))

            // Phase 1: Collect training data
            _state = .collecting(progress: .zero)
            await stateCallback?(_state)

            logger.info("Starting data collection from \(directories.count) directories")

            let collectionResult = await dataCollector.collectTrainingData(
                from: directories,
                mapping: options.tagFieldMapping
            ) { [weak self] progress in
                guard let self = self else { return }
                let detailed = DetailedProgress(
                    processed: progress.processed,
                    total: progress.total,
                    currentFile: progress.currentFile?.lastPathComponent
                )
                await self.updateState(.collecting(progress: detailed))
                await stateCallback?(await self.state)
            }

            guard !collectionResult.tracks.isEmpty else {
                _state = .failed(error: CoordinatorError.noDataFound.localizedDescription)
                await stateCallback?(_state)
                throw CoordinatorError.noDataFound
            }

            logger.info("Collected \(collectionResult.tracks.count) tracks from \(collectionResult.scannedCount) files")

            // Log excluded files (pre-flight validation failures)
            if !collectionResult.excludedFiles.isEmpty {
                logger.warning("Excluded \(collectionResult.excludedFiles.count) files that would cause issues:")
                for excluded in collectionResult.excludedFiles {
                    logger.warning("  - \(excluded.url.lastPathComponent): \(excluded.reason)")
                }
            }

            // Extract file names for progress display
            let allFileNames = collectionResult.tracks.map { URL(fileURLWithPath: $0.id).lastPathComponent }

            // Phase 2: Fail-fast viability check before paying for feature
            // extraction. The authoritative per-tag filtering (and per-tag
            // skip reporting) happens inside trainTwoPhase.
            let discoveredTags = await dataCollector.discoverTags(from: collectionResult.tracks)
            let minSamples = options.configuration.minSamplesPerTag
            let viableTagCount = discoveredTags.filter { tag, count in
                (options.selectedTags?.contains(tag) ?? true) && count >= minSamples
            }.count

            guard viableTagCount > 0 else {
                let errorDetails = "No tags have sufficient samples (min: \(minSamples))"
                _state = .failed(error: errorDetails)
                await stateCallback?(_state)
                throw CoordinatorError.insufficientData(details: errorDetails)
            }

            logger.info("\(viableTagCount) viable tags discovered")

            // Phase 3: Extract features (with checkpoint support)

            // Check for existing checkpoint
            var tracksToProcess = collectionResult.tracks
            var resumedFromCheckpoint = false

            if let checkpoint = checkpointManager.load(modelName: options.modelName) {
                // Verify checkpoint is compatible with current training run (including tag validation)
                let compatibility = checkpointManager.isCheckpointCompatible(
                    checkpoint,
                    sourceDirectories: directories,
                    currentTracks: collectionResult.tracks,
                    currentConfig: dataCollector.featureExtractionConfig
                )

                switch compatibility {
                case .compatible(let warning):
                    if let warning = warning {
                        logger.warning("Checkpoint warning: \(warning)")
                    }

                    let checkpointTrackIDs = checkpoint.getProcessedTrackIDs()
                    let checkpointTracks = checkpoint.getTaggedTracks()

                    // Count how many collected tracks already have features in checkpoint
                    // IMPORTANT: Use features from checkpoint but tags from current collection
                    // This ensures we train on current tags even when resuming
                    var tracksWithCheckpointFeatures: [TaggedTrack] = []
                    var tracksNeedingFeatures: [TaggedTrack] = []

                    for track in collectionResult.tracks {
                        if checkpointTrackIDs.contains(track.id),
                           let checkpointTrack = checkpointTracks.first(where: { $0.id == track.id }),
                           let features = checkpointTrack.features {
                            // Use features from checkpoint but CURRENT tags from collection
                            let updatedTrack = TaggedTrack(
                                id: track.id,
                                tags: track.tags,  // Use current tags, not checkpoint tags
                                features: features,
                                tagsByCategory: track.tagsByCategory  // Current categories too
                            )
                            tracksWithCheckpointFeatures.append(updatedTrack)
                        } else {
                            tracksNeedingFeatures.append(track)
                        }
                    }

                    if !tracksWithCheckpointFeatures.isEmpty {
                        logger.info("Resuming from checkpoint: \(tracksWithCheckpointFeatures.count) tracks already have features, \(tracksNeedingFeatures.count) remaining")
                        // Combine: tracks with features first, then those needing features
                        tracksToProcess = tracksWithCheckpointFeatures + tracksNeedingFeatures
                        resumedFromCheckpoint = true
                    }

                case .incompatible(let reason):
                    logger.info("Checkpoint incompatible: \(reason.description) - starting fresh")
                    // Delete the incompatible checkpoint
                    try? checkpointManager.delete(modelName: options.modelName)
                }
            }

            let initialProgress = DetailedProgress(
                processed: resumedFromCheckpoint ? tracksToProcess.filter { $0.features != nil }.count : 0,
                total: collectionResult.tracks.count,
                currentFile: nil,
                allFiles: allFileNames
            )
            _state = .extractingFeatures(progress: initialProgress)
            await stateCallback?(_state)

            logger.info("Extracting features for \(collectionResult.tracks.count) tracks\(resumedFromCheckpoint ? " (resumed from checkpoint)" : "")")

            let concurrency = recommendedExtractionConcurrency()
            logger.info("Feature extraction concurrency: \(concurrency)")

            let tracksWithFeatures = await dataCollector.extractFeatures(
                for: tracksToProcess,
                concurrency: concurrency,
                modelName: options.modelName,
                sourceDirectories: directories,
                checkpointManager: checkpointManager
            ) { [weak self] progress in
                guard let self = self else { return }
                let detailed = DetailedProgress(
                    processed: progress.processed,
                    total: progress.total,
                    currentFile: progress.currentFile?.lastPathComponent,
                    allFiles: allFileNames
                )
                await self.updateState(.extractingFeatures(progress: detailed))
                await stateCallback?(await self.state)
            }

            // Filter to only tracks with features
            let validTracks = tracksWithFeatures.filter { track in
                guard let features = track.features else { return false }
                return !features.isEmpty
            }
            let tracksWithInvalidFeatures = tracksWithFeatures.count - validTracks.count

            guard !validTracks.isEmpty else {
                let errorDetails = "Feature extraction failed for all tracks"
                _state = .failed(error: errorDetails)
                await stateCallback?(_state)
                throw CoordinatorError.insufficientData(details: errorDetails)
            }

            logger.info("Extracted features for \(validTracks.count) tracks (\(tracksWithInvalidFeatures) had invalid features)")

            // Phases 4+5: two-phase training — Phase A (Stage 1 perception
            // models) then Phase B (Stage 2 judgment models), with checkpoint
            // phase marker, pairing enforcement, and paired metadata.
            return try await trainTwoPhase(
                tracks: validTracks,
                options: options,
                sourceDirectories: directories,
                totalTracksScanned: collectionResult.scannedCount,
                tracksWithInvalidFeatures: tracksWithInvalidFeatures,
                stateCallback: stateCallback
            )

        } catch let error as CoordinatorError {
            throw error
        } catch {
            let errorMessage = error.localizedDescription
            _state = .failed(error: errorMessage)
            await stateCallback?(_state)
            throw CoordinatorError.trainingFailed(reason: errorMessage)
        }
    }

    // MARK: - Two-Phase Training (Stage 1 perception → Stage 2 judgment)

    /// Two-phase training over tracks that already carry extracted features.
    ///
    /// **Phase A** trains the Stage 1 (perception) models — multi-class
    /// groups plus binary classifiers for perception-stage tags — writes
    /// metadata with a fresh `stage1ModelVersion`, then saves a checkpoint
    /// marked `.phaseACompleted`. **Phase B** runs the just-trained Stage 1
    /// over the library via `JudgmentDataGenerator` (cached features only —
    /// no audio re-extraction), trains one judgment model per Timing tag,
    /// writes the paired metadata (`stage1ModelVersion` +
    /// `judgmentColumnNames`), and deletes the checkpoint.
    ///
    /// **Crash recovery:** a crash after the Phase A marker resumes directly
    /// into Phase B without retraining Stage 1. **Pairing enforcement:**
    /// Phase B refuses to run against a Stage 1 model version different from
    /// the checkpointed one — drift means Stage 1 changed after the
    /// checkpoint, so both stages retrain together.
    ///
    /// - Parameters:
    ///   - tracks: Tracks with extracted features and per-track
    ///     `tagsByCategory` (drives both category-complete filtering and the
    ///     judgment labels).
    ///   - options: Training options; `tagsByCategory` + the stage registry
    ///     decide which tags are Stage 2's exclusive domain.
    ///   - explicitOutputDirectory: Where models land. nil uses the standard
    ///     models directory for `options.modelName`.
    ///   - sourceDirectories: Recorded in the Phase A checkpoint.
    ///   - totalTracksScanned: For the summary; defaults to `tracks.count`.
    ///   - tracksWithInvalidFeatures: For the summary.
    ///   - stageRegistry: Category → stage mapping (Timing → judgment).
    ///   - predictorOverride: Test seam; nil loads the production
    ///     `Stage1Predictor` from the trained models on disk.
    ///   - bpmLookup: nil uses the production ID3 TBPM read.
    ///   - durationLookup: nil uses the production AVAudioFile header read.
    public func trainTwoPhase(
        tracks: [TaggedTrack],
        options: TrainingOptions = TrainingOptions(),
        outputDirectory explicitOutputDirectory: URL? = nil,
        sourceDirectories: [URL] = [],
        totalTracksScanned: Int? = nil,
        tracksWithInvalidFeatures: Int = 0,
        stageRegistry: TagStageRegistry = TagStageRegistry(),
        predictorOverride: (any Stage1Predictor)? = nil,
        bpmLookup: (@Sendable (String) async -> Float?)? = nil,
        durationLookup: (@Sendable (String) async -> Float?)? = nil,
        stateCallback: (@Sendable (State) async -> Void)? = nil
    ) async throws -> TrainingSummary {
        do {
            let outputDirectory: URL
            if let explicitOutputDirectory {
                outputDirectory = explicitOutputDirectory
            } else {
                outputDirectory = try await modelManager.modelsDirectory()
                    .appendingPathComponent(options.modelName)
            }
            let metadataURL = outputDirectory.appendingPathComponent("\(options.modelName).json")

            let trainingConfig = TrainingConfig(
                validationSplit: options.configuration.validationSplit,
                minSamplesPerTag: options.configuration.minSamplesPerTag,
                maxNegativeRatio: options.configuration.maxNegativeRatio,
                randomSeed: options.configuration.randomSeed,
                mixupEnabled: options.configuration.enableMixup,
                mixupAlpha: options.configuration.mixupAlpha,
                mixupRatio: options.configuration.mixupRatio,
                labelSmoothingEnabled: options.configuration.enableLabelSmoothing,
                labelSmoothingFactor: options.configuration.labelSmoothingFactor,
                contrastiveLearningEnabled: options.configuration.enableContrastiveLoss,
                treeMaxDepth: options.configuration.treeMaxDepth,
                treeIterations: options.configuration.treeIterations,
                treeStepSize: options.configuration.treeStepSize
            )

            // Tag → category lookup and stage partition. Timing (judgment)
            // tags are Stage 2's exclusive domain: never binary-trained.
            var tagToCategory: [String: String] = [:]
            for (category, categoryTags) in options.tagsByCategory {
                for tag in categoryTags {
                    tagToCategory[tag.lowercased()] = category
                }
            }
            let judgmentCategories = Set(stageRegistry.categories(in: .judgment).map { $0.lowercased() })
            func isJudgmentTag(_ tag: String) -> Bool {
                guard let category = tagToCategory[tag.lowercased()] else { return false }
                return judgmentCategories.contains(category.lowercased())
            }

            // Discover and filter viable tags
            let discoveredTags = await dataCollector.discoverTags(from: tracks)
            var viableTags: [String] = []
            var skippedTagDetails: [SkippedTag] = []
            let minSamples = options.configuration.minSamplesPerTag

            for (tag, count) in discoveredTags {
                guard options.selectedTags?.contains(tag) ?? true else { continue }
                if count >= minSamples {
                    viableTags.append(tag)
                } else {
                    skippedTagDetails.append(SkippedTag(
                        tag: tag,
                        reason: .insufficientSamples(required: minSamples),
                        sampleCount: count
                    ))
                    logger.info("Skipping tag '\(tag)': \(count) samples < \(minSamples) required")
                }
            }

            guard !viableTags.isEmpty else {
                throw CoordinatorError.insufficientData(
                    details: "No tags have sufficient samples (min: \(minSamples))"
                )
            }

            let judgmentViable = viableTags.filter { isJudgmentTag($0) }.sorted()
            let perceptionViable = viableTags.filter { !isJudgmentTag($0) }

            logger.info("Stage partition: \(perceptionViable.count) perception tags, \(judgmentViable.count) judgment tags")

            // ---- Resume: a phaseACompleted checkpoint jumps straight to
            // Phase B, but ONLY against the exact Stage 1 it recorded. ----
            if let checkpoint = checkpointManager.load(modelName: options.modelName),
               case .phaseACompleted(let checkpointedVersion) = checkpoint.phase {
                let onDiskVersion = (try? ModelMetadata.load(from: metadataURL))?.stage1ModelVersion
                if onDiskVersion == checkpointedVersion {
                    logger.info("Resuming into Phase B: checkpointed Stage 1 version '\(checkpointedVersion)' verified on disk — Stage 1 will NOT be retrained")
                    _state = .training(progress: 0.8, currentTag: "[judgment]")
                    await stateCallback?(_state)

                    let outcome = try await runPhaseB(
                        tracks: tracks,
                        judgmentTags: judgmentViable,
                        stage1ModelVersion: checkpointedVersion,
                        modelName: options.modelName,
                        outputDirectory: outputDirectory,
                        metadataURL: metadataURL,
                        tagToCategory: tagToCategory,
                        trainingConfig: trainingConfig,
                        stageRegistry: stageRegistry,
                        predictorOverride: predictorOverride,
                        bpmLookup: bpmLookup,
                        durationLookup: durationLookup
                    )

                    _state = .complete(modelName: options.modelName)
                    await stateCallback?(_state)

                    // Stage 1 was trained by the interrupted run; this
                    // summary reports the resumed work (Phase B) plus the
                    // Stage 1 groups recorded in metadata.
                    let metadata = try? ModelMetadata.load(from: metadataURL)
                    return TrainingSummary(
                        modelName: options.modelName,
                        tagResults: outcome.results.map(Self.toTagTrainingResult),
                        tagGroupResults: (metadata?.tagGroups ?? []).map { group in
                            TagGroupInfo(
                                groupName: group.groupName,
                                classes: group.classes,
                                accuracy: group.accuracy,
                                perClassAccuracy: group.perClassAccuracy
                            )
                        },
                        skippedTagDetails: skippedTagDetails + outcome.skippedTags.map(Self.toSkippedTag),
                        totalTracksScanned: totalTracksScanned ?? tracks.count,
                        tracksUsedForTraining: tracks.count,
                        tracksWithInvalidFeatures: tracksWithInvalidFeatures,
                        averageAccuracy: metadata?.accuracy ?? 0.0,
                        modelURL: outputDirectory
                    )
                } else {
                    logger.warning("Phase B refused: checkpointed Stage 1 version '\(checkpointedVersion)' does not match on-disk '\(onDiskVersion ?? "none")'. Stage 2 must pair with the Stage 1 it was generated from — retraining BOTH stages.")
                    try? checkpointManager.delete(modelName: options.modelName)
                }
            }

            // ================ PHASE A: Stage 1 (perception) ================
            _state = .training(progress: 0.0, currentTag: nil)
            await stateCallback?(_state)

            // Clean stale models from previous training runs. Only on a
            // fresh Phase A — a Phase B resume must keep Stage 1 on disk.
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: outputDirectory.path) {
                logger.info("Cleaning existing model directory: \(outputDirectory.path)")
                try fileManager.removeItem(at: outputDirectory)
            }
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            logger.info("Training models in \(outputDirectory.path)")

            // Phase A-1: Train multi-class classifiers for tag groups
            var multiClassResults: [MultiClassTrainingResult] = []
            var tagsHandledByGroups: Set<String> = []

            let multiClassGenerator = MultiClassTrainingDataGenerator(registry: options.tagGroupRegistry)
            let viableGroupNames = multiClassGenerator.viableGroups(
                from: tracks,
                minSamplesPerClass: minSamples,
                minClasses: 2
            )

            logger.info("Found \(viableGroupNames.count) viable tag groups for multi-class training")

            for groupName in viableGroupNames {
                guard let trainingData = multiClassGenerator.generateTrainingData(
                    for: groupName,
                    from: tracks,
                    minSamplesPerClass: minSamples
                ) else {
                    continue
                }

                logger.info("Training multi-class group '\(groupName)' with classes: \(trainingData.classes.joined(separator: ", "))")

                await self.updateState(.training(progress: 0.0, currentTag: "[\(groupName)]"))
                await stateCallback?(_state)

                do {
                    let result = try await modelTrainer.trainMultiClassModel(
                        data: trainingData,
                        outputDirectory: outputDirectory,
                        validationSplit: options.configuration.validationSplit,
                        useLabelSmoothing: options.configuration.enableLabelSmoothing,
                        smoothingFactor: options.configuration.labelSmoothingFactor,
                        config: trainingConfig
                    )
                    multiClassResults.append(result)

                    for className in result.classes {
                        tagsHandledByGroups.insert(className)
                        tagsHandledByGroups.insert(className.lowercased())
                    }

                    logger.info("Multi-class '\(groupName)' trained with accuracy: \(result.accuracy)")
                } catch {
                    logger.error("Failed to train multi-class group '\(groupName)': \(error.localizedDescription)")
                    // Continue with other groups
                }
            }

            // Phase A-2: Binary classifiers for ungrouped PERCEPTION tags.
            // Judgment tags were already partitioned out above.
            let binaryTags = perceptionViable.filter { tag in
                if tagsHandledByGroups.contains(tag) || tagsHandledByGroups.contains(tag.lowercased()) {
                    logger.info("Tag '\(tag)' covered by multi-class group, skipping binary training")
                    return false
                }
                if options.tagGroupRegistry.isGrouped(tag) {
                    logger.info("Tag '\(tag)' belongs to a tag group, skipping binary training")
                    return false
                }
                return true
            }

            logger.info("Training \(binaryTags.count) binary classifiers (after filtering \(perceptionViable.count - binaryTags.count) grouped tags)")

            // Category-complete negative filtering: negatives are restricted
            // to tracks assessed for the tag's category (absence = unknown).
            let (trainingResults, skippedDuringTraining) = try await modelTrainer.trainModelsWithReport(
                from: tracks,
                tags: binaryTags,
                outputDirectory: outputDirectory,
                config: trainingConfig,
                categorizedTags: options.tagsByCategory
            ) { [weak self] progress in
                guard let self = self else { return }
                let multiClassWeight = 0.2  // Multi-class gets 20% of progress
                let binaryProgress = multiClassWeight + (progress.fraction * (1.0 - multiClassWeight))
                await self.updateState(.training(
                    progress: binaryProgress,
                    currentTag: progress.currentTag
                ))
                await stateCallback?(await self.state)
            }

            for skipped in skippedDuringTraining {
                skippedTagDetails.append(Self.toSkippedTag(skipped))
                logger.warning("Tag '\(skipped.tag)' produced no training set: \(skipped.reason.description)")
            }

            guard !trainingResults.isEmpty || !multiClassResults.isEmpty else {
                throw CoordinatorError.trainingFailed(reason: "No models were successfully trained")
            }

            // Phase A-3: Save metadata with the new Stage 1 version. Written
            // BEFORE the checkpoint marker: a crash between the two writes
            // leaves no marker, so the next run safely retrains Phase A.
            _state = .packaging
            await stateCallback?(_state)

            logger.info("Packaging model with metadata")

            let trainedTagNames = trainingResults.map { $0.tag }
            let tagGroupInfos = multiClassResults.map { result in
                TagGroupInfo(
                    groupName: result.groupName,
                    classes: result.classes,
                    accuracy: result.accuracy,
                    perClassAccuracy: result.perClassAccuracy
                )
            }

            var stage1Accuracies = trainingResults.map { $0.validationAccuracy }
            stage1Accuracies.append(contentsOf: multiClassResults.map { $0.accuracy })
            let stage1AvgAccuracy = stage1Accuracies.isEmpty ? 0.0 :
                stage1Accuracies.reduce(0, +) / Double(stage1Accuracies.count)

            let stage1ModelVersion = UUID().uuidString
            let featureDimension: Int
            if let dimension = tracks.first(where: { !($0.features ?? []).isEmpty })?.features?.count {
                featureDimension = dimension
            } else {
                featureDimension = await dataCollector.getActualFeatureDimension()
            }

            let metadata = createModelMetadata(
                name: options.modelName,
                tags: trainedTagNames,
                tagGroups: tagGroupInfos,
                trainingFileCount: tracks.count,
                accuracy: stage1AvgAccuracy,
                categorizedTags: options.tagsByCategory,
                featureDimension: featureDimension,
                stage1ModelVersion: stage1ModelVersion
            )

            do {
                try metadata.save(to: metadataURL)
            } catch {
                throw CoordinatorError.saveFailed(reason: error.localizedDescription)
            }

            // Phase A checkpoint marker: a crash anywhere after this line
            // resumes directly into Phase B against this exact Stage 1.
            let phaseACheckpoint = TrainingCheckpoint(
                modelName: options.modelName,
                sourceDirectories: sourceDirectories,
                processedTracks: tracks,
                totalTracksDiscovered: totalTracksScanned ?? tracks.count,
                featureExtractionConfig: dataCollector.featureExtractionConfig,
                phase: .phaseACompleted(stage1ModelVersion: stage1ModelVersion)
            )
            do {
                try checkpointManager.save(phaseACheckpoint)
            } catch {
                logger.warning("Failed to save Phase A checkpoint: \(error.localizedDescription) — a crash during Phase B will retrain Stage 1")
            }

            // ================ PHASE B: Stage 2 (judgment) ================
            _state = .training(progress: 0.8, currentTag: "[judgment]")
            await stateCallback?(_state)

            let outcome = try await runPhaseB(
                tracks: tracks,
                judgmentTags: judgmentViable,
                stage1ModelVersion: stage1ModelVersion,
                modelName: options.modelName,
                outputDirectory: outputDirectory,
                metadataURL: metadataURL,
                tagToCategory: tagToCategory,
                trainingConfig: trainingConfig,
                stageRegistry: stageRegistry,
                predictorOverride: predictorOverride,
                bpmLookup: bpmLookup,
                durationLookup: durationLookup
            )

            _state = .complete(modelName: options.modelName)
            await stateCallback?(_state)

            logger.info("Two-phase training complete: \(trainedTagNames.count) binary, \(multiClassResults.count) multi-class, \(outcome.results.count) judgment models")

            let tagResults = trainingResults.map(Self.toTagTrainingResult)
                + outcome.results.map(Self.toTagTrainingResult)
            var allAccuracies = stage1Accuracies
            allAccuracies.append(contentsOf: outcome.results.map { $0.validationAccuracy })
            let avgAccuracy = allAccuracies.isEmpty ? 0.0 :
                allAccuracies.reduce(0, +) / Double(allAccuracies.count)

            return TrainingSummary(
                modelName: options.modelName,
                tagResults: tagResults,
                tagGroupResults: tagGroupInfos,
                skippedTagDetails: skippedTagDetails + outcome.skippedTags.map(Self.toSkippedTag),
                totalTracksScanned: totalTracksScanned ?? tracks.count,
                tracksUsedForTraining: tracks.count,
                tracksWithInvalidFeatures: tracksWithInvalidFeatures,
                averageAccuracy: avgAccuracy,
                modelURL: outputDirectory
            )
        } catch {
            _state = .failed(error: error.localizedDescription)
            await stateCallback?(_state)
            throw error
        }
    }

    /// Result of Phase B (Stage 2 judgment training).
    private struct PhaseBOutcome {
        let results: [TrainingResult]
        let skippedTags: [SkippedTrainingTag]
        let columnNames: [String]?
    }

    /// Phase B: generate judgment rows from the (already-extracted) library
    /// via Stage 1, train one judgment model per Timing tag, write the
    /// paired metadata, and delete the checkpoint. Shared by the fresh path
    /// and the crash-resume path — both arrive here with a verified
    /// `stage1ModelVersion`.
    private func runPhaseB(
        tracks: [TaggedTrack],
        judgmentTags: [String],
        stage1ModelVersion: String,
        modelName: String,
        outputDirectory: URL,
        metadataURL: URL,
        tagToCategory: [String: String],
        trainingConfig: TrainingConfig,
        stageRegistry: TagStageRegistry,
        predictorOverride: (any Stage1Predictor)?,
        bpmLookup: (@Sendable (String) async -> Float?)?,
        durationLookup: (@Sendable (String) async -> Float?)?
    ) async throws -> PhaseBOutcome {
        let phaseAMetadata = try? ModelMetadata.load(from: metadataURL)

        var results: [TrainingResult] = []
        var skippedTags: [SkippedTrainingTag] = []
        var columnNames: [String]?

        if judgmentTags.isEmpty {
            logger.info("Phase B: no viable judgment-stage tags — Stage 2 skipped")
        } else {
            let predictor: any Stage1Predictor
            if let predictorOverride {
                predictor = predictorOverride
            } else {
                predictor = try ProductionStage1Predictor.load(
                    from: outputDirectory,
                    metadata: phaseAMetadata
                )
            }

            let generator = JudgmentDataGenerator(
                predictor: predictor,
                bpmLookup: bpmLookup ?? Self.makeProductionBPMLookup(),
                durationLookup: durationLookup ?? Self.productionDurationLookup,
                registry: stageRegistry
            )

            logger.info("Phase B: generating judgment rows from \(tracks.count) tracks (cached features only — no audio re-extraction)")
            let (rows, skippedTracks) = try await generator.generate(from: tracks)
            if skippedTracks > 0 {
                logger.warning("Phase B: \(skippedTracks) tracks skipped — no cached features")
            }

            (results, skippedTags, columnNames) = try await modelTrainer.trainJudgmentModels(
                rows: rows,
                tags: judgmentTags,
                outputDirectory: outputDirectory,
                config: trainingConfig
            )
        }

        // Paired metadata: identical Stage 1 fields plus the judgment schema,
        // with the trained judgment tags merged into the per-category map.
        if let phaseAMetadata {
            var mergedTags = phaseAMetadata.tags
            for result in results {
                let category = tagToCategory[result.tag.lowercased()] ?? "Timing"
                var categoryTags = mergedTags[category] ?? []
                if !categoryTags.contains(result.tag) {
                    categoryTags.append(result.tag)
                    categoryTags.sort()
                }
                mergedTags[category] = categoryTags
            }

            let paired = ModelMetadata(
                name: phaseAMetadata.name,
                version: phaseAMetadata.version,
                pipelineVersion: phaseAMetadata.pipelineVersion,
                trainedAt: phaseAMetadata.trainedAt,
                trainingFileCount: phaseAMetadata.trainingFileCount,
                categories: Array(mergedTags.keys).sorted(),
                tags: mergedTags,
                tagGroups: phaseAMetadata.tagGroups,
                accuracy: phaseAMetadata.accuracy,
                featureDimension: phaseAMetadata.featureDimension,
                calibratorTemperature: phaseAMetadata.calibratorTemperature,
                descriptiveSubCategories: phaseAMetadata.descriptiveSubCategories,
                tagThresholds: phaseAMetadata.tagThresholds,
                stage1ModelVersion: stage1ModelVersion,
                judgmentColumnNames: columnNames
            )
            do {
                try paired.save(to: metadataURL)
            } catch {
                throw CoordinatorError.saveFailed(reason: error.localizedDescription)
            }
        } else {
            logger.warning("Phase B: no Phase A metadata found at \(metadataURL.path) — paired metadata not written")
        }

        // Both phases complete — the checkpoint has served its purpose
        do {
            try checkpointManager.delete(modelName: modelName)
            logger.info("Deleted checkpoint for completed two-phase training")
        } catch {
            logger.warning("Failed to delete checkpoint: \(error.localizedDescription)")
        }

        return PhaseBOutcome(results: results, skippedTags: skippedTags, columnNames: columnNames)
    }

    // MARK: - Production BPM/duration lookups (Phase B)

    /// BPM from the ID3 TBPM frame (`ID3Manager.readTags` →
    /// `ExtractedTags.bpm`), read at generation time. A per-file metadata
    /// read — no audio decode. nil when absent or unparseable (the
    /// generator substitutes the -1.0 sentinel).
    private static func makeProductionBPMLookup() -> @Sendable (String) async -> Float? {
        let id3Manager = ID3Manager()
        return { trackID in
            let url = URL(fileURLWithPath: trackID)
            guard let tags = try? await id3Manager.readTags(from: url),
                  let bpmString = tags.bpm,
                  let bpm = Float(bpmString.trimmingCharacters(in: .whitespaces)),
                  bpm > 0 else {
                return nil
            }
            return bpm
        }
    }

    /// Track duration in seconds from the audio file header
    /// (`AVAudioFile.length / processingFormat.sampleRate`) — a header read,
    /// no decode, no feature extraction.
    private static let productionDurationLookup: @Sendable (String) async -> Float? = { trackID in
        let url = URL(fileURLWithPath: trackID)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return Float(Double(file.length) / sampleRate)
    }

    // MARK: - Result mapping helpers

    private static func toTagTrainingResult(_ result: TrainingResult) -> TagTrainingResult {
        TagTrainingResult(
            tag: result.tag,
            trainingAccuracy: result.trainingAccuracy,
            validationAccuracy: result.validationAccuracy,
            positiveCount: result.positiveCount,
            negativeCount: result.negativeCount
        )
    }

    private static func toSkippedTag(_ skipped: SkippedTrainingTag) -> SkippedTag {
        switch skipped.reason {
        case .insufficientPositives(let found, let required):
            return SkippedTag(
                tag: skipped.tag,
                reason: .insufficientSamples(required: required),
                sampleCount: found
            )
        case .noTrustedNegatives(let positives):
            return SkippedTag(
                tag: skipped.tag,
                reason: .noTrustedNegatives,
                sampleCount: positives
            )
        }
    }

    /// Create model metadata for the trained model
    /// - Parameters:
    ///   - name: Model name
    ///   - tags: Tags that were trained (binary classifiers)
    ///   - tagGroups: Multi-class tag group info
    ///   - trainingFileCount: Number of files used for training
    ///   - accuracy: Average validation accuracy
    ///   - categorizedTags: Tags organized by category from training options
    ///   - featureDimension: The actual feature dimension used during training (1280, 1680, 2192, or 2960)
    ///   - stage1ModelVersion: Version of the Stage 1 model set that Stage 2 pairs with
    ///   - judgmentColumnNames: Stage 2 input schema (nil before/without Phase B)
    /// - Returns: ModelMetadata instance
    public func createModelMetadata(
        name: String,
        tags: [String],
        tagGroups: [TagGroupInfo] = [],
        trainingFileCount: Int,
        accuracy: Double,
        categorizedTags: [String: Set<String>] = [:],
        featureDimension: Int = 1680,
        stage1ModelVersion: String? = nil,
        judgmentColumnNames: [String]? = nil
    ) -> ModelMetadata {
        // Use provided categories or fall back to grouping all under "General"
        let tagsByCategory = groupTagsByCategory(tags, categorizedTags: categorizedTags)

        // Get current feature pipeline version
        let pipelineVersion = currentPipelineVersion()

        // Convert TagGroupInfo to TagGroupMetadata
        let tagGroupMetadata = tagGroups.map { info in
            TagGroupMetadata(
                groupName: info.groupName,
                classes: info.classes,
                accuracy: info.accuracy,
                perClassAccuracy: info.perClassAccuracy
            )
        }

        // Organize descriptive tags by sub-category
        let descriptiveTags = tagsByCategory["Descriptive"] ?? []
        let organizedDescriptive = DescriptiveTagMapping.organize(descriptiveTags)
        let subCategoriesDict: [String: [String]] = Dictionary(
            uniqueKeysWithValues: organizedDescriptive.map { ($0.key.rawValue, $0.value) }
        )

        return ModelMetadata(
            name: name,
            version: "1.0.0",
            pipelineVersion: pipelineVersion.versionHash,
            trainedAt: Date(),
            trainingFileCount: trainingFileCount,
            categories: Array(tagsByCategory.keys).sorted(),
            tags: tagsByCategory,
            tagGroups: tagGroupMetadata,
            accuracy: accuracy,
            featureDimension: featureDimension,
            descriptiveSubCategories: subCategoriesDict.isEmpty ? nil : subCategoriesDict,
            stage1ModelVersion: stage1ModelVersion,
            judgmentColumnNames: judgmentColumnNames
        )
    }

    /// Reset the coordinator to idle state
    public func reset() {
        _state = .idle
    }

    // MARK: - Private Methods

    private func updateState(_ newState: State) {
        _state = newState
    }

    private func groupTagsByCategory(_ tags: [String], categorizedTags: [String: Set<String>]) -> [String: [String]] {
        // If categories were provided, use them
        guard !categorizedTags.isEmpty else {
            // Fallback to putting all under "General"
            return ["General": tags.sorted()]
        }

        // Build a lookup from tag name (lowercased) to category
        var tagToCategory: [String: String] = [:]
        for (category, categoryTags) in categorizedTags {
            for tag in categoryTags {
                tagToCategory[tag.lowercased()] = category
            }
        }

        // Group trained tags by their category
        var result: [String: [String]] = [:]
        for tag in tags {
            let category = tagToCategory[tag.lowercased()] ?? "Descriptive"
            result[category, default: []].append(tag)
        }

        // Sort tags within each category
        for (category, categoryTags) in result {
            result[category] = categoryTags.sorted()
        }

        return result
    }

    /// Get the current feature pipeline version
    /// - Returns: The multi-window EffNet-based feature pipeline configuration.
    ///   Encodes the window fractions so models trained on windowed features
    ///   carry a versionHash distinct from pre-windowing models.
    public func currentPipelineVersion() -> FeaturePipelineVersion {
        .current(for: dataCollector.featureExtractionConfig)
    }

    private func recommendedExtractionConcurrency() -> Int {
        let processInfo = ProcessInfo.processInfo
        let cores = max(2, processInfo.activeProcessorCount)
        let physicalMemory = Double(processInfo.physicalMemory)

        // Target 80% of physical memory with a moderately aggressive per-track estimate.
        let targetMemory = physicalMemory * 0.8
        let perTrackBytes = 32.0 * 1024.0 * 1024.0
        let memoryCap = max(2, Int(targetMemory / perTrackBytes))

        // Cap by cores and a safe upper bound to avoid UI starvation.
        let coreCap = cores * 4
        let hardCap = physicalMemory >= (64.0 * 1024.0 * 1024.0 * 1024.0) ? 96 : 48

        return max(2, min(memoryCap, min(coreCap, hardCap)))
    }
}
