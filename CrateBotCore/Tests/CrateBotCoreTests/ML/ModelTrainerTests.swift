import XCTest
@testable import CrateBotCore

final class ModelTrainerTests: XCTestCase {

    // MARK: - TrainingConfig Tests

    func testTrainingConfigDefaultValues() {
        let config = TrainingConfig()

        XCTAssertEqual(config.validationSplit, 0.2, accuracy: 0.001)
        XCTAssertEqual(config.minSamplesPerTag, 50)
        XCTAssertEqual(config.maxNegativeRatio, 1.5, accuracy: 0.001)
        XCTAssertEqual(config.randomSeed, 42)
    }

    func testTrainingConfigCustomValues() {
        let config = TrainingConfig(
            validationSplit: 0.3,
            minSamplesPerTag: 100,
            maxNegativeRatio: 2.0,
            randomSeed: 123
        )

        XCTAssertEqual(config.validationSplit, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.minSamplesPerTag, 100)
        XCTAssertEqual(config.maxNegativeRatio, 2.0, accuracy: 0.001)
        XCTAssertEqual(config.randomSeed, 123)
    }

    func testTrainingConfigTreeParametersAreUsed() {
        let config = TrainingConfig(
            treeMaxDepth: 8,
            treeIterations: 150,
            treeStepSize: 0.25
        )

        XCTAssertEqual(config.treeMaxDepth, 8)
        XCTAssertEqual(config.treeIterations, 150)
        XCTAssertEqual(config.treeStepSize, 0.25, accuracy: 0.001)
    }

    func testTrainingConfigDefaultTreeParameters() {
        let config = TrainingConfig()

        XCTAssertEqual(config.treeMaxDepth, 6)
        XCTAssertEqual(config.treeIterations, 100)
        XCTAssertEqual(config.treeStepSize, 0.3, accuracy: 0.001)
    }

    // MARK: - TrainingResult Tests

    func testTrainingResultInitialization() {
        let modelURL = URL(fileURLWithPath: "/tmp/test.mlmodel")
        let result = TrainingResult(
            tag: "House",
            modelURL: modelURL,
            trainingAccuracy: 0.95,
            validationAccuracy: 0.90,
            positiveCount: 100,
            negativeCount: 200
        )

        XCTAssertEqual(result.tag, "House")
        XCTAssertEqual(result.modelURL, modelURL)
        XCTAssertEqual(result.trainingAccuracy, 0.95, accuracy: 0.001)
        XCTAssertEqual(result.validationAccuracy, 0.90, accuracy: 0.001)
        XCTAssertEqual(result.positiveCount, 100)
        XCTAssertEqual(result.negativeCount, 200)
    }

    // MARK: - TrainingProgress Tests

    func testTrainingProgressInitialization() {
        let progress = TrainingProgress(
            phase: .training,
            currentTag: "Techno",
            tagsCompleted: 5,
            totalTags: 10
        )

        XCTAssertEqual(progress.phase, .training)
        XCTAssertEqual(progress.currentTag, "Techno")
        XCTAssertEqual(progress.tagsCompleted, 5)
        XCTAssertEqual(progress.totalTags, 10)
    }

    func testTrainingProgressFraction() {
        let progress1 = TrainingProgress(
            phase: .training,
            currentTag: "House",
            tagsCompleted: 5,
            totalTags: 10
        )
        XCTAssertEqual(progress1.fraction, 0.5, accuracy: 0.001)

        let progress2 = TrainingProgress(
            phase: .preparing,
            currentTag: "House",
            tagsCompleted: 0,
            totalTags: 10
        )
        XCTAssertEqual(progress2.fraction, 0.0, accuracy: 0.001)

        let progress3 = TrainingProgress(
            phase: .complete,
            currentTag: nil,
            tagsCompleted: 10,
            totalTags: 10
        )
        XCTAssertEqual(progress3.fraction, 1.0, accuracy: 0.001)
    }

    func testTrainingProgressFractionZeroTotal() {
        let progress = TrainingProgress(
            phase: .complete,
            currentTag: nil,
            tagsCompleted: 0,
            totalTags: 0
        )
        XCTAssertEqual(progress.fraction, 0.0, accuracy: 0.001)
    }

    func testTrainingProgressPhases() {
        // Test all phases can be created
        let preparing = TrainingProgress(phase: .preparing, currentTag: "Test", tagsCompleted: 0, totalTags: 1)
        let training = TrainingProgress(phase: .training, currentTag: "Test", tagsCompleted: 0, totalTags: 1)
        let validating = TrainingProgress(phase: .validating, currentTag: "Test", tagsCompleted: 0, totalTags: 1)
        let saving = TrainingProgress(phase: .saving, currentTag: "Test", tagsCompleted: 0, totalTags: 1)
        let complete = TrainingProgress(phase: .complete, currentTag: nil, tagsCompleted: 1, totalTags: 1)

        XCTAssertEqual(preparing.phase, .preparing)
        XCTAssertEqual(training.phase, .training)
        XCTAssertEqual(validating.phase, .validating)
        XCTAssertEqual(saving.phase, .saving)
        XCTAssertEqual(complete.phase, .complete)
    }

    // MARK: - TrainerError Tests

    func testTrainerErrorInsufficientDataDescription() {
        let error = TrainerError.insufficientData(tag: "House", count: 20, required: 50)
        XCTAssertEqual(
            error.errorDescription,
            "Insufficient data for tag 'House': 20 samples, 50 required"
        )
    }

    func testTrainerErrorNoFeaturesAvailableDescription() {
        let error = TrainerError.noFeaturesAvailable
        XCTAssertEqual(
            error.errorDescription,
            "No tracks with features available for training"
        )
    }

    func testTrainerErrorTrainingFailedDescription() {
        let error = TrainerError.trainingFailed(tag: "Techno", reason: "Model diverged")
        XCTAssertEqual(
            error.errorDescription,
            "Training failed for tag 'Techno': Model diverged"
        )
    }

    func testTrainerErrorSaveFailedDescription() {
        let error = TrainerError.saveFailed(tag: "Chill", reason: "Disk full")
        XCTAssertEqual(
            error.errorDescription,
            "Failed to save model for tag 'Chill': Disk full"
        )
    }

    // MARK: - ModelTrainer Initialization Tests

    func testModelTrainerInitialization() async {
        let trainer = ModelTrainer()
        XCTAssertNotNil(trainer)
    }

    func testModelTrainerInitializationWithCustomGenerator() async {
        let generator = BinaryTrainingDataGenerator()
        let trainer = ModelTrainer(dataGenerator: generator)
        XCTAssertNotNil(trainer)
    }

    // MARK: - PrepareDataFrame Tests

    func testPrepareDataFrameCreatesCorrectStructure() async throws {
        let trainer = ModelTrainer()

        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: [1.0, 2.0, 3.0]),
            TaggedTrack(id: "2", tags: ["House"], features: [4.0, 5.0, 6.0]),
            TaggedTrack(id: "3", tags: ["Techno"], features: [7.0, 8.0, 9.0]),
        ]

        let dataFrame = try await trainer.prepareDataFrame(
            for: "House",
            from: tracks,
            featureCount: 3
        )

        // Check column count (3 features + 1 label)
        XCTAssertEqual(dataFrame.columns.count, 4)

        // Check column names
        XCTAssertTrue(dataFrame.containsColumn("f0"))
        XCTAssertTrue(dataFrame.containsColumn("f1"))
        XCTAssertTrue(dataFrame.containsColumn("f2"))
        XCTAssertTrue(dataFrame.containsColumn("label"))

        // Check row count
        XCTAssertEqual(dataFrame.rows.count, 3)
    }

    func testPrepareDataFrameCorrectLabels() async throws {
        let trainer = ModelTrainer()

        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: [1.0, 2.0]),
            TaggedTrack(id: "2", tags: ["Techno"], features: [3.0, 4.0]),
        ]

        let dataFrame = try await trainer.prepareDataFrame(
            for: "House",
            from: tracks,
            featureCount: 2
        )

        let labels = dataFrame["label", String.self]
        XCTAssertEqual(Array(labels), ["positive", "negative"])
    }

    func testPrepareDataFrameSkipsTracksWithWrongFeatureCount() async throws {
        let trainer = ModelTrainer()

        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: [1.0, 2.0, 3.0]),
            TaggedTrack(id: "2", tags: ["House"], features: [4.0, 5.0]),  // Wrong count
            TaggedTrack(id: "3", tags: ["Techno"], features: [7.0, 8.0, 9.0]),
        ]

        let dataFrame = try await trainer.prepareDataFrame(
            for: "House",
            from: tracks,
            featureCount: 3
        )

        // Should only include 2 tracks (skipping the one with wrong feature count)
        XCTAssertEqual(dataFrame.rows.count, 2)
    }

    func testPrepareDataFrameSkipsTracksWithNilFeatures() async throws {
        let trainer = ModelTrainer()

        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: [1.0, 2.0]),
            TaggedTrack(id: "2", tags: ["House"], features: nil),
            TaggedTrack(id: "3", tags: ["Techno"], features: [3.0, 4.0]),
        ]

        let dataFrame = try await trainer.prepareDataFrame(
            for: "House",
            from: tracks,
            featureCount: 2
        )

        // Should only include 2 tracks (skipping the one with nil features)
        XCTAssertEqual(dataFrame.rows.count, 2)
    }

    // MARK: - TrainModels Tests

    func testTrainModelsThrowsNoFeaturesAvailable() async {
        let trainer = ModelTrainer()

        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: nil),
            TaggedTrack(id: "2", tags: ["Techno"], features: nil),
        ]

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            _ = try await trainer.trainModels(
                from: tracks,
                tags: ["House"],
                outputDirectory: tempDir
            )
            XCTFail("Expected noFeaturesAvailable error")
        } catch let error as TrainerError {
            if case .noFeaturesAvailable = error {
                // Expected
            } else {
                XCTFail("Expected noFeaturesAvailable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTrainModelsThrowsForEmptyFeatures() async {
        let trainer = ModelTrainer()

        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: []),
            TaggedTrack(id: "2", tags: ["Techno"], features: []),
        ]

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            _ = try await trainer.trainModels(
                from: tracks,
                tags: ["House"],
                outputDirectory: tempDir
            )
            XCTFail("Expected noFeaturesAvailable error")
        } catch let error as TrainerError {
            if case .noFeaturesAvailable = error {
                // Expected
            } else {
                XCTFail("Expected noFeaturesAvailable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTrainModelsSkipsTagsWithInsufficientData() async throws {
        let trainer = ModelTrainer()

        // Create tracks with fewer than 50 positive samples for "House"
        var tracks: [TaggedTrack] = []
        for i in 0..<10 {
            tracks.append(TaggedTrack(
                id: "house_\(i)",
                tags: ["House"],
                features: Array(repeating: Float(i), count: 10)
            ))
        }
        for i in 0..<100 {
            tracks.append(TaggedTrack(
                id: "other_\(i)",
                tags: ["Other"],
                features: Array(repeating: Float(i), count: 10)
            ))
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let results = try await trainer.trainModels(
            from: tracks,
            tags: ["House"],  // House has only 10 samples, below minimum 50
            outputDirectory: tempDir
        )

        // Should return empty results since House doesn't have enough samples
        XCTAssertEqual(results.count, 0)
    }

    func testTrainModelsCallsProgressCallback() async throws {
        let trainer = ModelTrainer()

        // Create minimal tracks (won't actually train due to insufficient data)
        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: [1.0, 2.0]),
        ]

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        actor ProgressTracker {
            var phases: [TrainingProgress.Phase] = []
            func addPhase(_ phase: TrainingProgress.Phase) {
                phases.append(phase)
            }
            func getPhases() -> [TrainingProgress.Phase] { phases }
        }

        let tracker = ProgressTracker()

        _ = try await trainer.trainModels(
            from: tracks,
            tags: ["House"],
            outputDirectory: tempDir
        ) { progress in
            await tracker.addPhase(progress.phase)
        }

        let phases = await tracker.getPhases()
        // Should have at least preparing and complete phases
        XCTAssertTrue(phases.contains(.preparing))
        XCTAssertTrue(phases.contains(.complete))
    }
}
