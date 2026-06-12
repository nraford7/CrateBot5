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

    /// trainModelsWithReport must surface skipped tags with the right reason:
    /// a tag with positives but zero trusted negatives (category-complete
    /// filtering excluded every candidate) lands as noTrustedNegatives, and a
    /// thin tag lands as insufficientPositives.
    func testTrainModelsWithReportSurfacesSkipReasons() async throws {
        let trainer = ModelTrainer()
        let config = TrainingConfig(minSamplesPerTag: 5)

        var tracks: [TaggedTrack] = []
        // "Peak" (Timing): 6 positives, and no OTHER track carries a Timing
        // tag, so every non-positive is an unknown — zero trusted negatives.
        for i in 0..<6 {
            tracks.append(TaggedTrack(
                id: "peak_\(i)",
                tags: ["Peak"],
                features: [Float(i), 1.0, 2.0, 3.0],
                tagsByCategory: ["Timing": ["Peak"]]
            ))
        }
        // Genre-only tracks: unknowns for the Timing category
        for i in 0..<4 {
            tracks.append(TaggedTrack(
                id: "house_\(i)",
                tags: ["House"],
                features: [Float(i), 4.0, 5.0, 6.0],
                tagsByCategory: ["Genre": ["House"]]
            ))
        }
        // "Rare" (Genre): only 2 positives, below minSamplesPerTag
        for i in 0..<2 {
            tracks.append(TaggedTrack(
                id: "rare_\(i)",
                tags: ["Rare"],
                features: [Float(i), 7.0, 8.0, 9.0],
                tagsByCategory: ["Genre": ["Rare"]]
            ))
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (results, skippedTags) = try await trainer.trainModelsWithReport(
            from: tracks,
            tags: ["Peak", "Rare"],
            outputDirectory: tempDir,
            config: config,
            categorizedTags: ["Timing": ["Peak"], "Genre": ["House", "Rare"]]
        )

        XCTAssertTrue(results.isEmpty, "Both tags should be skipped, not trained")
        XCTAssertEqual(skippedTags.count, 2)

        let reasonsByTag = Dictionary(uniqueKeysWithValues: skippedTags.map { ($0.tag, $0.reason) })
        XCTAssertEqual(reasonsByTag["Peak"], .noTrustedNegatives(positives: 6),
            "Positives but zero trusted negatives must surface as noTrustedNegatives with the real positive count")
        XCTAssertEqual(reasonsByTag["Rare"], .insufficientPositives(found: 2, required: 5),
            "A thin tag must surface as insufficientPositives")
    }

    // MARK: - Judgment (Stage 2) Training Tests

    /// Builds one Stage 2 row with a deterministic schema. `seed` drives the
    /// feature values so positives/negatives are separable.
    private func makeJudgmentRow(seed: Float, labels: Set<String>, trackID: String) -> JudgmentRow {
        let vector = JudgmentFeatureVector(
            binaryConfidences: ["Dark": seed, "Driving": 1 - seed],
            groupProbabilities: ["BassType": ["Punchy": seed / 2, "Walking": 1 - seed / 2]],
            bpm: 120 + seed * 20,
            durationSeconds: 300
        )
        return (features: vector, labels: labels, trackID: trackID)
    }

    private func makeSeparableRows(positiveTag: String = "Peak", negativeTag: String = "Build", count: Int = 15) -> [JudgmentRow] {
        var rows: [JudgmentRow] = []
        for i in 0..<count {
            rows.append(makeJudgmentRow(seed: Float.random(in: 0.7...1.0), labels: [positiveTag], trackID: "pos_\(i)"))
        }
        for i in 0..<count {
            rows.append(makeJudgmentRow(seed: Float.random(in: 0.0...0.3), labels: [negativeTag], trackID: "neg_\(i)"))
        }
        return rows
    }

    /// Stage 2 training: per Timing tag, a BoostedTree trained on the exact
    /// JudgmentFeatureVector schema, saved as `<tag>_judgment.mlmodel`, with
    /// NO augmentation — sample counts must equal the input rows exactly.
    func testTrainJudgmentModelsSavesPerTagJudgmentModels() async throws {
        let rows = makeSeparableRows()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let trainer = ModelTrainer()
        let config = TrainingConfig(minSamplesPerTag: 10)
        let (results, skipped, columnNames) = try await trainer.trainJudgmentModels(
            rows: rows,
            outputDirectory: tempDir,
            config: config
        )

        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(Set(results.map(\.tag)), ["Peak", "Build"])
        XCTAssertEqual(columnNames, rows[0].features.columnNames,
            "Returned schema must be the exact JudgmentFeatureVector column order")

        let peak = try XCTUnwrap(results.first { $0.tag == "Peak" })
        XCTAssertEqual(peak.modelURL.lastPathComponent, "Peak_judgment.mlmodel")
        XCTAssertTrue(FileManager.default.fileExists(atPath: peak.modelURL.path))
        // No mixup/noise on judgment features: counts equal the raw rows
        XCTAssertEqual(peak.positiveCount, 15)
        XCTAssertEqual(peak.negativeCount, 15)
        XCTAssertGreaterThan(peak.validationAccuracy, 0.5,
            "Separable rows should train a better-than-chance judgment model")
    }

    func testTrainJudgmentModelsReportsThinAndNegativelessTags() async throws {
        // "Everywhere" is on every row → zero trusted negatives.
        // "Rare" is on 3 rows → below minSamplesPerTag.
        var rows: [JudgmentRow] = []
        for i in 0..<15 {
            rows.append(makeJudgmentRow(seed: 0.9, labels: ["Peak", "Everywhere"], trackID: "p_\(i)"))
        }
        for i in 0..<15 {
            let labels: Set<String> = i < 3 ? ["Build", "Everywhere", "Rare"] : ["Build", "Everywhere"]
            rows.append(makeJudgmentRow(seed: 0.1, labels: labels, trackID: "b_\(i)"))
        }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let trainer = ModelTrainer()
        let (results, skipped, _) = try await trainer.trainJudgmentModels(
            rows: rows,
            outputDirectory: tempDir,
            config: TrainingConfig(minSamplesPerTag: 10)
        )

        XCTAssertEqual(Set(results.map(\.tag)), ["Peak", "Build"])
        let reasons = Dictionary(uniqueKeysWithValues: skipped.map { ($0.tag, $0.reason) })
        XCTAssertEqual(reasons["Rare"], .insufficientPositives(found: 3, required: 10))
        XCTAssertEqual(reasons["Everywhere"], .noTrustedNegatives(positives: 30))
    }

    func testTrainJudgmentModelsEmptyRowsReturnsEmpty() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let trainer = ModelTrainer()
        let (results, skipped, columnNames) = try await trainer.trainJudgmentModels(
            rows: [],
            outputDirectory: tempDir
        )
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertNil(columnNames)
    }

    /// Doc-comment contract: requested tags with no rows are reported as
    /// skipped — including when there are NO rows at all.
    func testTrainJudgmentModelsEmptyRowsReportsRequestedTagsSkipped() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let trainer = ModelTrainer()
        let (results, skipped, columnNames) = try await trainer.trainJudgmentModels(
            rows: [],
            tags: ["Peak", "Build"],
            outputDirectory: tempDir,
            config: TrainingConfig(minSamplesPerTag: 10)
        )
        XCTAssertTrue(results.isEmpty)
        XCTAssertNil(columnNames)
        XCTAssertEqual(skipped.map(\.tag), ["Peak", "Build"],
            "Requested tags with zero rows must surface as skipped, never vanish silently")
        XCTAssertEqual(skipped.first?.reason, .insufficientPositives(found: 0, required: 10))
    }

    /// Schema is anchored to the MAJORITY of rows, not the first row: an
    /// aberrant first row (e.g. one intermittent Stage 1 classifier failure)
    /// must be the row that gets dropped — not the 30 well-formed ones.
    func testTrainJudgmentModelsAberrantFirstRowDoesNotDiscardMajority() async throws {
        var rows = makeSeparableRows()
        let majoritySchema = rows[0].features.columnNames
        let alien = JudgmentFeatureVector(
            binaryConfidences: ["Dark": 0.9],  // "Driving" column missing
            groupProbabilities: ["BassType": ["Punchy": 0.4, "Walking": 0.6]],
            bpm: 120,
            durationSeconds: 300
        )
        rows.insert((features: alien, labels: Set(["Peak"]), trackID: "alien_first"), at: 0)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let trainer = ModelTrainer()
        let (results, skipped, columnNames) = try await trainer.trainJudgmentModels(
            rows: rows,
            outputDirectory: tempDir,
            config: TrainingConfig(minSamplesPerTag: 10)
        )

        XCTAssertEqual(columnNames, majoritySchema,
            "The majority column layout must win, not the first row's")
        XCTAssertEqual(Set(results.map(\.tag)), ["Peak", "Build"],
            "All well-formed rows must train; only the aberrant row is dropped")
        XCTAssertTrue(skipped.isEmpty)
        let peak = try XCTUnwrap(results.first { $0.tag == "Peak" })
        XCTAssertEqual(peak.positiveCount, 15, "The aberrant first row must be excluded from training")
    }

    func testTrainJudgmentModelsDropsSchemaMismatchedRows() async throws {
        var rows = makeSeparableRows()
        // One row with a different Stage 1 schema (extra binary tag) — must be
        // dropped, never silently mixed into a model with different columns.
        let alien = JudgmentFeatureVector(
            binaryConfidences: ["Dark": 0.9, "Driving": 0.1, "Extra": 0.5],
            groupProbabilities: [:],
            bpm: 120,
            durationSeconds: 300
        )
        rows.append((features: alien, labels: Set(["Peak"]), trackID: "alien"))

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let trainer = ModelTrainer()
        let (results, _, _) = try await trainer.trainJudgmentModels(
            rows: rows,
            outputDirectory: tempDir,
            config: TrainingConfig(minSamplesPerTag: 10)
        )

        let peak = try XCTUnwrap(results.first { $0.tag == "Peak" })
        XCTAssertEqual(peak.positiveCount, 15, "Schema-mismatched row must not be trained on")
    }

    func testTrainJudgmentModelsRespectsExplicitTagListAndSanitizesNames() async throws {
        let rows = makeSeparableRows(positiveTag: "Set Starter", negativeTag: "Build")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let trainer = ModelTrainer()
        let (results, skipped, _) = try await trainer.trainJudgmentModels(
            rows: rows,
            tags: ["Set Starter", "Ghost"],
            outputDirectory: tempDir,
            config: TrainingConfig(minSamplesPerTag: 10)
        )

        XCTAssertEqual(results.map(\.tag), ["Set Starter"])
        XCTAssertEqual(results[0].modelURL.lastPathComponent, "Set_Starter_judgment.mlmodel")
        // "Build" was not requested — absent from results AND skips
        XCTAssertFalse(skipped.contains { $0.tag == "Build" })
        // "Ghost" was requested but has no rows — surfaced, not silent
        XCTAssertEqual(
            skipped.first { $0.tag == "Ghost" }?.reason,
            .insufficientPositives(found: 0, required: 10)
        )
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
