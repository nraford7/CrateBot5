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

            public var description: String {
                switch self {
                case .insufficientSamples(let required):
                    return "Needs \(required)+ samples"
                case .trainingFailed(let error):
                    return "Training failed: \(error)"
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

            // Phase 2: Discover and filter tags
            let discoveredTags = await dataCollector.discoverTags(from: collectionResult.tracks)

            // Filter tags based on selection and minimum samples
            var viableTags: [String] = []
            var skippedTagDetails: [SkippedTag] = []

            let minSamples = options.configuration.minSamplesPerTag

            for (tag, count) in discoveredTags {
                // Check if tag is in selected set (or if no selection, include all)
                let isSelected = options.selectedTags?.contains(tag) ?? true

                if isSelected {
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
            }

            guard !viableTags.isEmpty else {
                let errorDetails = "No tags have sufficient samples (min: \(minSamples))"
                _state = .failed(error: errorDetails)
                await stateCallback?(_state)
                throw CoordinatorError.insufficientData(details: errorDetails)
            }

            logger.info("Training \(viableTags.count) tags, skipping \(skippedTagDetails.count)")

            // Phase 3: Extract features (with checkpoint support)

            // Check for existing checkpoint
            var tracksToProcess = collectionResult.tracks
            var resumedFromCheckpoint = false

            if let checkpoint = checkpointManager.load(modelName: options.modelName) {
                // Verify checkpoint is compatible with current training run (including tag validation)
                let compatibility = checkpointManager.isCheckpointCompatible(
                    checkpoint,
                    sourceDirectories: directories,
                    currentTracks: collectionResult.tracks
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
                                features: features
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

            let tracksWithFeatures = await dataCollector.extractFeatures(
                for: tracksToProcess,
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
            let validTracks = tracksWithFeatures.filter { $0.features != nil && !$0.features!.isEmpty }
            let tracksWithInvalidFeatures = tracksWithFeatures.count - validTracks.count

            guard !validTracks.isEmpty else {
                let errorDetails = "Feature extraction failed for all tracks"
                _state = .failed(error: errorDetails)
                await stateCallback?(_state)
                throw CoordinatorError.insufficientData(details: errorDetails)
            }

            logger.info("Extracted features for \(validTracks.count) tracks (\(tracksWithInvalidFeatures) had invalid features)")

            // Phase 4: Train models
            _state = .training(progress: 0.0, currentTag: nil)
            await stateCallback?(_state)

            let outputDirectory = try await modelManager.modelsDirectory()
                .appendingPathComponent(options.modelName)

            // Clean stale models from previous training runs
            // This prevents old .mlmodel files from persisting when retraining
            // with a different set of tags (Fresh Eyes issue #3)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: outputDirectory.path) {
                logger.info("Cleaning existing model directory: \(outputDirectory.path)")
                try fileManager.removeItem(at: outputDirectory)
            }
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

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
                contrastiveLearningEnabled: options.configuration.enableContrastiveLoss
            )

            logger.info("Training models in \(outputDirectory.path)")

            // Phase 4a: Train multi-class classifiers for tag groups
            var multiClassResults: [MultiClassTrainingResult] = []
            var tagsHandledByGroups: Set<String> = []

            let multiClassGenerator = MultiClassTrainingDataGenerator(registry: options.tagGroupRegistry)
            let viableGroupNames = multiClassGenerator.viableGroups(
                from: validTracks,
                minSamplesPerClass: minSamples,
                minClasses: 2
            )

            logger.info("Found \(viableGroupNames.count) viable tag groups for multi-class training")

            for groupName in viableGroupNames {
                guard let trainingData = multiClassGenerator.generateTrainingData(
                    for: groupName,
                    from: validTracks,
                    minSamplesPerClass: minSamples
                ) else {
                    continue
                }

                logger.info("Training multi-class group '\(groupName)' with classes: \(trainingData.classes.joined(separator: ", "))")

                // Update state to show current group
                await self.updateState(.training(progress: 0.0, currentTag: "[\(groupName)]"))
                await stateCallback?(_state)

                do {
                    let result = try await modelTrainer.trainMultiClassModel(
                        data: trainingData,
                        outputDirectory: outputDirectory,
                        validationSplit: options.configuration.validationSplit
                    )
                    multiClassResults.append(result)

                    // Track which tags are now handled by this group
                    for className in result.classes {
                        tagsHandledByGroups.insert(className)
                        // Also insert lowercase version for matching
                        tagsHandledByGroups.insert(className.lowercased())
                    }

                    logger.info("Multi-class '\(groupName)' trained with accuracy: \(result.accuracy)")
                } catch {
                    logger.error("Failed to train multi-class group '\(groupName)': \(error.localizedDescription)")
                    // Continue with other groups
                }
            }

            // Phase 4b: Filter out tags that are covered by multi-class groups
            let binaryTags = viableTags.filter { tag in
                // Exclude if the tag is directly in a group
                if tagsHandledByGroups.contains(tag) || tagsHandledByGroups.contains(tag.lowercased()) {
                    logger.info("Tag '\(tag)' covered by multi-class group, skipping binary training")
                    return false
                }
                // Also check if the tag belongs to any group via the registry
                if options.tagGroupRegistry.isGrouped(tag) {
                    logger.info("Tag '\(tag)' belongs to a tag group, skipping binary training")
                    return false
                }
                return true
            }

            logger.info("Training \(binaryTags.count) binary classifiers (after filtering \(viableTags.count - binaryTags.count) grouped tags)")

            // Phase 4c: Train binary classifiers for remaining tags
            let trainingResults = try await modelTrainer.trainModels(
                from: validTracks,
                tags: binaryTags,
                outputDirectory: outputDirectory,
                config: trainingConfig
            ) { [weak self] progress in
                guard let self = self else { return }
                // Adjust progress to account for multi-class training phase
                let multiClassWeight = 0.2  // Multi-class gets 20% of progress
                let binaryProgress = multiClassWeight + (progress.fraction * (1.0 - multiClassWeight))
                await self.updateState(.training(
                    progress: binaryProgress,
                    currentTag: progress.currentTag
                ))
                await stateCallback?(await self.state)
            }

            // Check that we have at least some trained models (either multi-class or binary)
            guard !trainingResults.isEmpty || !multiClassResults.isEmpty else {
                let errorDetails = "No models were successfully trained"
                _state = .failed(error: errorDetails)
                await stateCallback?(_state)
                throw CoordinatorError.trainingFailed(reason: errorDetails)
            }

            // Calculate average accuracy (combining binary and multi-class)
            var allAccuracies = trainingResults.map { $0.validationAccuracy }
            allAccuracies.append(contentsOf: multiClassResults.map { $0.accuracy })
            let avgAccuracy = allAccuracies.isEmpty ? 0.0 :
                allAccuracies.reduce(0, +) / Double(allAccuracies.count)

            // Phase 5: Save metadata
            _state = .packaging
            await stateCallback?(_state)

            logger.info("Packaging model with metadata")

            // Collect all trained tags (binary classifiers)
            let trainedTagNames = trainingResults.map { $0.tag }

            // Convert multi-class results to TagGroupInfo for metadata
            let tagGroupInfos = multiClassResults.map { result in
                TagGroupInfo(
                    groupName: result.groupName,
                    classes: result.classes,
                    accuracy: result.accuracy,
                    perClassAccuracy: result.perClassAccuracy
                )
            }

            let metadata = createModelMetadata(
                name: options.modelName,
                tags: trainedTagNames,
                tagGroups: tagGroupInfos,
                trainingFileCount: validTracks.count,
                accuracy: avgAccuracy,
                categorizedTags: options.tagsByCategory
            )

            let metadataURL = outputDirectory.appendingPathComponent("\(options.modelName).json")

            do {
                try metadata.save(to: metadataURL)
            } catch {
                let errorDetails = "Failed to save metadata: \(error.localizedDescription)"
                _state = .failed(error: errorDetails)
                await stateCallback?(_state)
                throw CoordinatorError.saveFailed(reason: error.localizedDescription)
            }

            // Clean up checkpoint after successful training
            do {
                try checkpointManager.delete(modelName: options.modelName)
                logger.info("Deleted checkpoint for completed training")
            } catch {
                logger.warning("Failed to delete checkpoint: \(error.localizedDescription)")
            }

            // Complete
            _state = .complete(modelName: options.modelName)
            await stateCallback?(_state)

            logger.info("Training complete: \(trainedTagNames.count) binary models, \(multiClassResults.count) multi-class groups, avg accuracy: \(avgAccuracy)")

            // Convert training results to detailed tag results
            let tagResults = trainingResults.map { result in
                TagTrainingResult(
                    tag: result.tag,
                    trainingAccuracy: result.trainingAccuracy,
                    validationAccuracy: result.validationAccuracy,
                    positiveCount: result.positiveCount,
                    negativeCount: result.negativeCount
                )
            }

            return TrainingSummary(
                modelName: options.modelName,
                tagResults: tagResults,
                tagGroupResults: tagGroupInfos,
                skippedTagDetails: skippedTagDetails,
                totalTracksScanned: collectionResult.scannedCount,
                tracksUsedForTraining: validTracks.count,
                tracksWithInvalidFeatures: tracksWithInvalidFeatures,
                averageAccuracy: avgAccuracy,
                modelURL: outputDirectory
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

    /// Create model metadata for the trained model
    /// - Parameters:
    ///   - name: Model name
    ///   - tags: Tags that were trained (binary classifiers)
    ///   - tagGroups: Multi-class tag group info
    ///   - trainingFileCount: Number of files used for training
    ///   - accuracy: Average validation accuracy
    ///   - categorizedTags: Tags organized by category from training options
    /// - Returns: ModelMetadata instance
    public func createModelMetadata(
        name: String,
        tags: [String],
        tagGroups: [TagGroupInfo] = [],
        trainingFileCount: Int,
        accuracy: Double,
        categorizedTags: [String: Set<String>] = [:]
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
            descriptiveSubCategories: subCategoriesDict.isEmpty ? nil : subCategoriesDict
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
    /// - Returns: The EffNet-based feature pipeline configuration
    public func currentPipelineVersion() -> FeaturePipelineVersion {
        // Return EffNet-based feature pipeline configuration
        // EffNet produces 1280-dimensional embeddings from mel spectrograms
        FeaturePipelineVersion(
            extractorVersions: ["effnet": "v1"],
            windowingParams: FeaturePipelineVersion.WindowingParams(
                windowSize: 400,    // 25ms at 16kHz
                hopSize: 160,       // 10ms at 16kHz
                fftSize: 512        // EffNet FFT size
            ),
            normalizationParams: FeaturePipelineVersion.NormalizationParams(
                method: "log_mel",
                perFeature: false
            )
        )
    }
}
