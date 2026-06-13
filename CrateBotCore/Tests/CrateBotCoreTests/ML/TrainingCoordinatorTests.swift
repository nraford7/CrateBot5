import XCTest
@testable import CrateBotCore

final class TrainingCoordinatorTests: XCTestCase {

    // MARK: - State Tests

    func testInitialStateIsIdle() async {
        let coordinator = TrainingCoordinator()
        let state = await coordinator.state
        XCTAssertEqual(state, .idle)
    }

    func testStateEquality() {
        // Test idle
        XCTAssertEqual(TrainingCoordinator.State.idle, TrainingCoordinator.State.idle)

        // Test collecting with DetailedProgress
        let progress50 = TrainingCoordinator.DetailedProgress(processed: 50, total: 100, currentFile: "test.mp3")
        let progress70 = TrainingCoordinator.DetailedProgress(processed: 70, total: 100, currentFile: "test.mp3")
        let progress30 = TrainingCoordinator.DetailedProgress(processed: 30, total: 100, currentFile: "test.mp3")

        XCTAssertEqual(
            TrainingCoordinator.State.collecting(progress: progress50),
            TrainingCoordinator.State.collecting(progress: progress50)
        )
        XCTAssertNotEqual(
            TrainingCoordinator.State.collecting(progress: progress50),
            TrainingCoordinator.State.collecting(progress: progress70)
        )

        // Test extractingFeatures with DetailedProgress
        XCTAssertEqual(
            TrainingCoordinator.State.extractingFeatures(progress: progress30),
            TrainingCoordinator.State.extractingFeatures(progress: progress30)
        )

        // Test training
        XCTAssertEqual(
            TrainingCoordinator.State.training(progress: 0.5, currentTag: "House"),
            TrainingCoordinator.State.training(progress: 0.5, currentTag: "House")
        )
        XCTAssertNotEqual(
            TrainingCoordinator.State.training(progress: 0.5, currentTag: "House"),
            TrainingCoordinator.State.training(progress: 0.5, currentTag: "Techno")
        )

        // Test packaging
        XCTAssertEqual(TrainingCoordinator.State.packaging, TrainingCoordinator.State.packaging)

        // Test complete
        XCTAssertEqual(
            TrainingCoordinator.State.complete(modelName: "TestModel"),
            TrainingCoordinator.State.complete(modelName: "TestModel")
        )
        XCTAssertNotEqual(
            TrainingCoordinator.State.complete(modelName: "TestModel"),
            TrainingCoordinator.State.complete(modelName: "OtherModel")
        )

        // Test failed
        XCTAssertEqual(
            TrainingCoordinator.State.failed(error: "Error A"),
            TrainingCoordinator.State.failed(error: "Error A")
        )
        XCTAssertNotEqual(
            TrainingCoordinator.State.failed(error: "Error A"),
            TrainingCoordinator.State.failed(error: "Error B")
        )

        // Test different states
        XCTAssertNotEqual(TrainingCoordinator.State.idle, TrainingCoordinator.State.packaging)
        XCTAssertNotEqual(
            TrainingCoordinator.State.collecting(progress: progress50),
            TrainingCoordinator.State.extractingFeatures(progress: progress50)
        )
    }

    // MARK: - TrainingOptions Tests

    func testTrainingOptionsDefaultValues() {
        let options = TrainingCoordinator.TrainingOptions()

        XCTAssertEqual(options.modelName, "CustomModel")
        XCTAssertNil(options.selectedTags)
        // validationSplit and minSamplesPerTag now live in configuration
        XCTAssertEqual(options.configuration.validationSplit, 0.2, accuracy: 0.001)
        XCTAssertEqual(options.configuration.minSamplesPerTag, 50)
    }

    func testTrainingOptionsCustomValues() {
        let selectedTags: Set<String> = ["House", "Techno", "Ambient"]
        var config = TrainingConfiguration.default
        config.validationSplit = 0.3
        config.minSamplesPerTag = 100

        let options = TrainingCoordinator.TrainingOptions(
            modelName: "MyCustomModel",
            selectedTags: selectedTags,
            configuration: config
        )

        XCTAssertEqual(options.modelName, "MyCustomModel")
        XCTAssertEqual(options.selectedTags, selectedTags)
        // validationSplit and minSamplesPerTag now accessed via configuration
        XCTAssertEqual(options.configuration.validationSplit, 0.3, accuracy: 0.001)
        XCTAssertEqual(options.configuration.minSamplesPerTag, 100)
    }

    // MARK: - TrainingSummary Tests

    func testTrainingSummaryInitialization() {
        let modelURL = URL(fileURLWithPath: "/tmp/models/TestModel")
        let tagResults = [
            TrainingCoordinator.TagTrainingResult(tag: "House", trainingAccuracy: 0.90, validationAccuracy: 0.85, positiveCount: 100, negativeCount: 200),
            TrainingCoordinator.TagTrainingResult(tag: "Techno", trainingAccuracy: 0.92, validationAccuracy: 0.88, positiveCount: 120, negativeCount: 240),
            TrainingCoordinator.TagTrainingResult(tag: "Ambient", trainingAccuracy: 0.88, validationAccuracy: 0.82, positiveCount: 80, negativeCount: 160)
        ]
        let skippedTagDetails = [
            TrainingCoordinator.SkippedTag(tag: "Rare Tag", reason: .insufficientSamples(required: 50), sampleCount: 5)
        ]
        let summary = TrainingCoordinator.TrainingSummary(
            modelName: "TestModel",
            tagResults: tagResults,
            skippedTagDetails: skippedTagDetails,
            totalTracksScanned: 1000,
            tracksUsedForTraining: 800,
            tracksWithInvalidFeatures: 10,
            averageAccuracy: 0.85,
            modelURL: modelURL
        )

        XCTAssertEqual(summary.modelName, "TestModel")
        XCTAssertEqual(summary.trainedTags, ["House", "Techno", "Ambient"])
        XCTAssertEqual(summary.skippedTags, ["Rare Tag"])
        XCTAssertEqual(summary.totalTracksScanned, 1000)
        XCTAssertEqual(summary.averageAccuracy, 0.85, accuracy: 0.001)
        XCTAssertEqual(summary.modelURL, modelURL)
    }

    func testTrainingSummaryEmptyTags() {
        let modelURL = URL(fileURLWithPath: "/tmp/models/EmptyModel")
        let summary = TrainingCoordinator.TrainingSummary(
            modelName: "EmptyModel",
            tagResults: [],
            skippedTagDetails: [],
            totalTracksScanned: 0,
            tracksUsedForTraining: 0,
            tracksWithInvalidFeatures: 0,
            averageAccuracy: 0.0,
            modelURL: modelURL
        )

        XCTAssertTrue(summary.trainedTags.isEmpty)
        XCTAssertTrue(summary.skippedTags.isEmpty)
        XCTAssertEqual(summary.totalTracksScanned, 0)
    }

    // MARK: - createModelMetadata Tests

    func testCreateModelMetadataReturnsCorrectStructure() async {
        let coordinator = TrainingCoordinator()
        let tags = ["House", "Techno", "Ambient"]

        let metadata = await coordinator.createModelMetadata(
            name: "TestModel",
            tags: tags,
            trainingFileCount: 500,
            accuracy: 0.92
        )

        XCTAssertEqual(metadata.name, "TestModel")
        XCTAssertEqual(metadata.version, "1.0.0")
        XCTAssertEqual(metadata.trainingFileCount, 500)
        XCTAssertEqual(metadata.accuracy, 0.92)
        XCTAssertFalse(metadata.pipelineVersion.isEmpty)
        XCTAssertFalse(metadata.categories.isEmpty)

        // Check that tags are included
        let allTagsInMetadata = metadata.tags.values.flatMap { $0 }
        for tag in tags {
            XCTAssertTrue(allTagsInMetadata.contains(tag), "Expected tag '\(tag)' in metadata")
        }
    }

    func testCreateModelMetadataPipelineVersionHash() async {
        let coordinator = TrainingCoordinator()

        let metadata1 = await coordinator.createModelMetadata(
            name: "Model1",
            tags: ["House"],
            trainingFileCount: 100,
            accuracy: 0.9
        )

        let metadata2 = await coordinator.createModelMetadata(
            name: "Model2",
            tags: ["Techno"],
            trainingFileCount: 200,
            accuracy: 0.8
        )

        // Pipeline version should be consistent
        XCTAssertEqual(metadata1.pipelineVersion, metadata2.pipelineVersion)
    }

    func testCurrentPipelineVersionDiffersFromLegacySingleWindow() async {
        let coordinator = TrainingCoordinator()
        let current = await coordinator.currentPipelineVersion()

        // The windowed pipeline must produce a different versionHash than the
        // pre-windowing single-window pipeline, so newly trained models carry
        // a distinguishable ModelMetadata.pipelineVersion.
        XCTAssertNotEqual(
            current.versionHash,
            FeaturePipelineVersion.legacySingleWindow.versionHash
        )
        XCTAssertEqual(current.versionHash, FeaturePipelineVersion.current().versionHash)
    }

    func testCreateModelMetadataDateIsRecent() async {
        let coordinator = TrainingCoordinator()
        let beforeCreation = Date()

        let metadata = await coordinator.createModelMetadata(
            name: "TestModel",
            tags: ["House"],
            trainingFileCount: 100,
            accuracy: 0.9
        )

        let afterCreation = Date()

        XCTAssertGreaterThanOrEqual(metadata.trainedAt, beforeCreation)
        XCTAssertLessThanOrEqual(metadata.trainedAt, afterCreation)
    }

    func testCreateModelMetadataSavesDescriptiveSubCategories() async {
        let coordinator = TrainingCoordinator()

        // Include some descriptive tags that map to known sub-categories
        let categorizedTags: [String: Set<String>] = [
            "Genre": ["House", "Techno"],
            "Descriptive": ["Funky", "Dreamy", "Piano", "Punchy", "Broken"]
        ]
        let tags = ["House", "Techno", "Funky", "Dreamy", "Piano", "Punchy", "Broken"]

        let metadata = await coordinator.createModelMetadata(
            name: "TestModel",
            tags: tags,
            trainingFileCount: 500,
            accuracy: 0.85,
            categorizedTags: categorizedTags
        )

        // Verify descriptive sub-categories are populated
        XCTAssertNotNil(metadata.descriptiveSubCategories)

        let subCategories = metadata.descriptiveSubCategories!

        // Funky and Dreamy should be in Vibes
        XCTAssertNotNil(subCategories["Vibes"])
        XCTAssertTrue(subCategories["Vibes"]?.contains("Funky") ?? false)
        XCTAssertTrue(subCategories["Vibes"]?.contains("Dreamy") ?? false)

        // Piano should be in Instruments
        XCTAssertNotNil(subCategories["Instruments"])
        XCTAssertTrue(subCategories["Instruments"]?.contains("Piano") ?? false)

        // Punchy should be in BassType
        XCTAssertNotNil(subCategories["BassType"])
        XCTAssertTrue(subCategories["BassType"]?.contains("Punchy") ?? false)

        // Broken should be in Rhythm
        XCTAssertNotNil(subCategories["Rhythm"])
        XCTAssertTrue(subCategories["Rhythm"]?.contains("Broken") ?? false)
    }

    func testCreateModelMetadataNoDescriptiveSubCategoriesWhenNoDescriptiveTags() async {
        let coordinator = TrainingCoordinator()

        // Only genre tags, no descriptive tags
        let categorizedTags: [String: Set<String>] = [
            "Genre": ["House", "Techno"]
        ]
        let tags = ["House", "Techno"]

        let metadata = await coordinator.createModelMetadata(
            name: "TestModel",
            tags: tags,
            trainingFileCount: 100,
            accuracy: 0.9,
            categorizedTags: categorizedTags
        )

        // Should be nil when there are no descriptive tags to organize
        XCTAssertNil(metadata.descriptiveSubCategories)
    }

    func testCreateModelMetadataIncludesFeatureDimension() async {
        let coordinator = TrainingCoordinator()

        // Test with different feature dimensions
        let metadata1680 = await coordinator.createModelMetadata(
            name: "Test1680",
            tags: ["Tag1"],
            tagGroups: [],
            trainingFileCount: 100,
            accuracy: 0.9,
            categorizedTags: [:],
            featureDimension: 1680
        )
        XCTAssertEqual(metadata1680.featureDimension, 1680)

        let metadata2192 = await coordinator.createModelMetadata(
            name: "Test2192",
            tags: ["Tag1"],
            tagGroups: [],
            trainingFileCount: 100,
            accuracy: 0.9,
            categorizedTags: [:],
            featureDimension: 2192
        )
        XCTAssertEqual(metadata2192.featureDimension, 2192)

        let metadata1280 = await coordinator.createModelMetadata(
            name: "Test1280",
            tags: ["Tag1"],
            tagGroups: [],
            trainingFileCount: 100,
            accuracy: 0.9,
            categorizedTags: [:],
            featureDimension: 1280
        )
        XCTAssertEqual(metadata1280.featureDimension, 1280)
    }

    // MARK: - Reset Tests

    func testResetReturnsToIdleState() async {
        let coordinator = TrainingCoordinator()

        // Verify initial state is idle
        let initialState = await coordinator.state
        XCTAssertEqual(initialState, .idle)

        // Reset (even from idle) should remain idle
        await coordinator.reset()
        let afterReset = await coordinator.state
        XCTAssertEqual(afterReset, .idle)
    }

    // MARK: - CoordinatorError Tests

    func testCoordinatorErrorNoDataFoundDescription() {
        let error = CoordinatorError.noDataFound
        XCTAssertEqual(
            error.errorDescription,
            "No training data found in the specified directories"
        )
    }

    func testCoordinatorErrorInsufficientDataDescription() {
        let error = CoordinatorError.insufficientData(details: "Only 10 samples available")
        XCTAssertEqual(
            error.errorDescription,
            "Insufficient data for training: Only 10 samples available"
        )
    }

    func testCoordinatorErrorTrainingFailedDescription() {
        let error = CoordinatorError.trainingFailed(reason: "Model diverged during training")
        XCTAssertEqual(
            error.errorDescription,
            "Training failed: Model diverged during training"
        )
    }

    func testCoordinatorErrorSaveFailedDescription() {
        let error = CoordinatorError.saveFailed(reason: "Disk full")
        XCTAssertEqual(
            error.errorDescription,
            "Failed to save model: Disk full"
        )
    }

    func testCoordinatorErrorIsSendable() {
        // Verify CoordinatorError conforms to Sendable
        let error: Sendable = CoordinatorError.noDataFound
        XCTAssertNotNil(error)
    }

    // MARK: - Coordinator Initialization Tests

    func testCoordinatorInitialization() async {
        let coordinator = TrainingCoordinator()
        XCTAssertNotNil(coordinator)

        let state = await coordinator.state
        XCTAssertEqual(state, .idle)
    }

    func testCoordinatorInitializationWithDependencies() async {
        let dataCollector = TrainingDataCollector()
        let modelTrainer = ModelTrainer()
        let modelManager = ModelManager()

        let coordinator = TrainingCoordinator(
            dataCollector: dataCollector,
            modelTrainer: modelTrainer,
            modelManager: modelManager
        )

        XCTAssertNotNil(coordinator)

        let state = await coordinator.state
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Sub-category granularity audit (Task 1.1)

    /// Audit invariant for the descriptive sub-category lever: after a track's
    /// tagsByCategory is keyed by sub-category ("BassType", "Rhythm", "Vibes",
    /// ...) instead of "Descriptive", the TagStageRegistry must still classify
    /// those sub-categories as perception (Stage 1), NOT judgment (Stage 2).
    /// Otherwise the training-path isJudgmentTag check at TrainingCoordinator
    /// L587-597 would silently divert BassType/Rhythm tags out of Stage 1
    /// binary training — a regression.
    func testTagStageRegistryClassifiesDescriptiveSubCategoriesAsPerception() {
        let registry = TagStageRegistry()
        for sub in DescriptiveSubCategory.allCases {
            XCTAssertEqual(
                registry.stage(forCategory: sub.rawValue),
                .perception,
                "Descriptive sub-category \(sub.rawValue) must be perception, not judgment"
            )
        }
        // Timing remains the sole judgment category.
        XCTAssertEqual(registry.stage(forCategory: "Timing"), .judgment)
        XCTAssertEqual(registry.categories(in: .judgment), ["Timing"])
        // Sanity: judgment categories list does not accidentally include any sub-category.
        let judgment = Set(registry.categories(in: .judgment))
        for sub in DescriptiveSubCategory.allCases {
            XCTAssertFalse(judgment.contains(sub.rawValue),
                "Judgment category set must not contain descriptive sub-category \(sub.rawValue)")
        }
    }
}
