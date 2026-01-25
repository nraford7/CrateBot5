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

        /// Fraction of data to use for validation
        public let validationSplit: Double

        /// Minimum samples required per tag
        public let minSamplesPerTag: Int

        /// Mapping of ID3 fields to training categories
        public let tagFieldMapping: TrainingDataCollector.TagFieldMapping

        public init(
            modelName: String = "CustomModel",
            selectedTags: Set<String>? = nil,
            validationSplit: Double = 0.2,
            minSamplesPerTag: Int = 50,
            tagFieldMapping: TrainingDataCollector.TagFieldMapping = .default
        ) {
            self.modelName = modelName
            self.selectedTags = selectedTags
            self.validationSplit = validationSplit
            self.minSamplesPerTag = minSamplesPerTag
            self.tagFieldMapping = tagFieldMapping
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

        /// Detailed results for each trained tag
        public let tagResults: [TagTrainingResult]

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
            skippedTagDetails: [SkippedTag],
            totalTracksScanned: Int,
            tracksUsedForTraining: Int,
            tracksWithInvalidFeatures: Int,
            averageAccuracy: Double,
            modelURL: URL
        ) {
            self.modelName = modelName
            self.tagResults = tagResults
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

            for (tag, count) in discoveredTags {
                // Check if tag is in selected set (or if no selection, include all)
                let isSelected = options.selectedTags?.contains(tag) ?? true

                if isSelected {
                    if count >= options.minSamplesPerTag {
                        viableTags.append(tag)
                    } else {
                        skippedTagDetails.append(SkippedTag(
                            tag: tag,
                            reason: .insufficientSamples(required: options.minSamplesPerTag),
                            sampleCount: count
                        ))
                        logger.info("Skipping tag '\(tag)': \(count) samples < \(options.minSamplesPerTag) required")
                    }
                }
            }

            guard !viableTags.isEmpty else {
                let errorDetails = "No tags have sufficient samples (min: \(options.minSamplesPerTag))"
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

            let trainingConfig = TrainingConfig(
                validationSplit: options.validationSplit,
                minSamplesPerTag: options.minSamplesPerTag
            )

            logger.info("Training models in \(outputDirectory.path)")

            let trainingResults = try await modelTrainer.trainModels(
                from: validTracks,
                tags: viableTags,
                outputDirectory: outputDirectory,
                config: trainingConfig
            ) { [weak self] progress in
                guard let self = self else { return }
                await self.updateState(.training(
                    progress: progress.fraction,
                    currentTag: progress.currentTag
                ))
                await stateCallback?(await self.state)
            }

            guard !trainingResults.isEmpty else {
                let errorDetails = "No models were successfully trained"
                _state = .failed(error: errorDetails)
                await stateCallback?(_state)
                throw CoordinatorError.trainingFailed(reason: errorDetails)
            }

            // Calculate average accuracy
            let avgAccuracy = trainingResults.isEmpty ? 0.0 :
                trainingResults.map { $0.validationAccuracy }.reduce(0, +) / Double(trainingResults.count)

            // Phase 5: Save metadata
            _state = .packaging
            await stateCallback?(_state)

            logger.info("Packaging model with metadata")

            let trainedTagNames = trainingResults.map { $0.tag }
            let metadata = createModelMetadata(
                name: options.modelName,
                tags: trainedTagNames,
                trainingFileCount: validTracks.count,
                accuracy: avgAccuracy
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

            logger.info("Training complete: \(trainedTagNames.count) models, avg accuracy: \(avgAccuracy)")

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
    ///   - tags: Tags that were trained
    ///   - trainingFileCount: Number of files used for training
    ///   - accuracy: Average validation accuracy
    /// - Returns: ModelMetadata instance
    public func createModelMetadata(
        name: String,
        tags: [String],
        trainingFileCount: Int,
        accuracy: Double
    ) -> ModelMetadata {
        // Group tags by category (simplified - actual implementation might use tag registry)
        let tagsByCategory = groupTagsByCategory(tags)

        // Get current feature pipeline version
        let pipelineVersion = currentPipelineVersion()

        return ModelMetadata(
            name: name,
            version: "1.0.0",
            pipelineVersion: pipelineVersion.versionHash,
            trainedAt: Date(),
            trainingFileCount: trainingFileCount,
            categories: Array(tagsByCategory.keys).sorted(),
            tags: tagsByCategory,
            accuracy: accuracy
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

    private func groupTagsByCategory(_ tags: [String]) -> [String: [String]] {
        // Simplified categorization - in production this would use a tag registry
        // For now, put all tags under "General"
        return ["General": tags.sorted()]
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
