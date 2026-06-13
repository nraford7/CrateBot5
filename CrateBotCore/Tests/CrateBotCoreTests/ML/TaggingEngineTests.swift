import XCTest
import AVFoundation
@testable import CrateBotCore

final class TaggingEngineTests: XCTestCase {

    func testEngineInitialization() throws {
        let engine = try TaggingEngine()
        // Should initialize without error
        XCTAssertNotNil(engine)
    }

    func testAnalyzeWithSyntheticAudio() async throws {
        let engine = try TaggingEngine()

        // Create synthetic audio buffer (2.5 seconds of noise at 16kHz)
        // MelSpectrogramGenerator requires at least 33,024 samples
        let sampleRate: Double = 16000
        let samples = (0..<40000).map { _ in Float.random(in: -0.5...0.5) }
        let buffer = try createBuffer(samples: samples, sampleRate: sampleRate)

        let result = try await engine.analyze(buffer: buffer)

        // Verify embeddings
        XCTAssertEqual(result.embeddings.count, 1280, "Should have 1280-dim embeddings")
        XCTAssertEqual(result.genreActivations.count, 400, "Should have 400 genre activations")

        // Verify Essentia tags exist (may be empty if below threshold)
        XCTAssertNotNil(result.essentiaTags)

        // User predictions should be nil (no model loaded)
        XCTAssertNil(result.userPredictions)
    }

    func testHasUserModel() async throws {
        let engine = try TaggingEngine()

        // Initially no user model
        let hasModel = await engine.hasUserModel
        XCTAssertFalse(hasModel)
    }

    func testTaggingResultStructure() {
        let essentiaTags = EssentiaTags(
            genres: ["Electronic---House", "Electronic---Techno"],
            moods: ["energetic", "dark"],
            instruments: ["synthesizer", "drums"]
        )

        let result = TaggingResult(
            userPredictions: nil,
            essentiaTags: essentiaTags,
            embeddings: [Float](repeating: 0, count: 1280),
            genreActivations: [Float](repeating: 0, count: 400)
        )

        XCTAssertNil(result.userPredictions)
        XCTAssertEqual(result.essentiaTags.genres.count, 2)
        XCTAssertEqual(result.essentiaTags.moods.count, 2)
        XCTAssertEqual(result.essentiaTags.instruments.count, 2)
    }

    private func createBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }

    // MARK: - UserTagPredictions structured descriptive tests

    func testUserTagPredictionsHasStructuredDescriptive() {
        // Create predictions with organized descriptive output
        let predictions = UserTagPredictions(
            genre: "House",
            timing: "Peak",
            mood: "Uplifting",
            bassType: "Walking",
            rhythm: ["Broken", "Driving"],
            style: ["Afro"],
            vibes: ["Funky", "Dark"],
            instruments: ["Congas", "Organ"],
            vocalType: "Chanting",
            acapella: false
        )

        XCTAssertEqual(predictions.bassType, "Walking")
        XCTAssertEqual(predictions.rhythm, ["Broken", "Driving"])
        XCTAssertEqual(predictions.vocalType, "Chanting")
        XCTAssertFalse(predictions.acapella ?? true)
    }

    func testUserTagPredictionsDescriptiveArrayBackwardsCompat() {
        // Old-style descriptive array should still work
        let predictions = UserTagPredictions(
            genre: "House",
            timing: nil,
            mood: nil,
            descriptive: ["Funky", "Walking", "Congas"]
        )

        // The computed descriptive property returns tags in subcategory order:
        // bassType -> rhythm -> style -> vibes -> instruments -> vocalType
        // So "Walking" (bassType) comes first, then "Funky" (vibes), then "Congas" (instruments)
        XCTAssertEqual(predictions.descriptive, ["Walking", "Funky", "Congas"])

        // Verify the structured fields were populated correctly
        XCTAssertEqual(predictions.bassType, "Walking")
        XCTAssertEqual(predictions.vibes, ["Funky"])
        XCTAssertEqual(predictions.instruments, ["Congas"])
    }

    func testCustomTagsPreserved() {
        // Tags including custom ones not in DescriptiveTagMapping
        let predictions = UserTagPredictions(
            genre: "House",
            timing: "Peak",
            mood: "Happy",
            descriptive: ["Funky", "Groovy", "Driving", "Euphoric"]  // Groovy and Euphoric are custom
        )

        // Custom tags should be preserved
        XCTAssertTrue(predictions.customTags.contains("Groovy"), "Custom tag 'Groovy' should be preserved")
        XCTAssertTrue(predictions.customTags.contains("Euphoric"), "Custom tag 'Euphoric' should be preserved")

        // Known tags should be in their categories
        XCTAssertTrue(predictions.vibes.contains("Funky"), "Known tag 'Funky' should be in vibes")
        XCTAssertTrue(predictions.rhythm.contains("Driving"), "Known tag 'Driving' should be in rhythm")

        // All tags should appear in descriptive computed property
        let allDescriptive = predictions.descriptive
        XCTAssertTrue(allDescriptive.contains("Funky"))
        XCTAssertTrue(allDescriptive.contains("Groovy"))
        XCTAssertTrue(allDescriptive.contains("Driving"))
        XCTAssertTrue(allDescriptive.contains("Euphoric"))
    }

    // MARK: - Model loading with modelName parameter

    func testLoadModelWithModelName() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadata = ModelMetadata(
            name: "TestModel",
            version: "1.0",
            pipelineVersion: "1.0",
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Genre"],
            tags: ["Genre": ["House", "Techno"]],
            tagGroups: [],
            accuracy: 0.85,
            featureDimension: 1680
        )
        // Save metadata with model name (the new convention)
        let metadataURL = tempDir.appendingPathComponent("TestModel.json")
        try metadata.save(to: metadataURL)

        // Create a dummy .mlmodel directory (empty directory is enough for file listing)
        // Note: This won't be a valid model, but we can verify the metadata loading path
        let dummyModelDir = tempDir.appendingPathComponent("House.mlmodel")
        try FileManager.default.createDirectory(at: dummyModelDir, withIntermediateDirectories: true)

        let engine = try TaggingEngine()
        // loadModel will find the .mlmodel directory but fail to load it as a classifier
        // Still, we can verify the model name is returned correctly based on the parameter
        let (count, name) = try await engine.loadModel(from: tempDir, modelName: "TestModel")
        XCTAssertEqual(name, "TestModel", "Model name should match the provided modelName parameter")
        // No classifiers will actually load since the model file is empty
        XCTAssertEqual(count, 0)
    }

    // MARK: - Pipeline version compatibility

    func testLoadModelRejectsPreWindowingPipelineVersion() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Metadata stamped with the exact pre-windowing (single-window) pipeline hash
        let metadata = ModelMetadata(
            name: "OldModel",
            version: "1.0",
            pipelineVersion: FeaturePipelineVersion.legacySingleWindow.versionHash,
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Genre"],
            tags: ["Genre": ["House"]],
            featureDimension: 1680
        )
        try metadata.save(to: tempDir.appendingPathComponent("OldModel.json"))

        let dummyModelDir = tempDir.appendingPathComponent("House.mlmodel")
        try FileManager.default.createDirectory(at: dummyModelDir, withIntermediateDirectories: true)

        let engine = try TaggingEngine()
        do {
            _ = try await engine.loadModel(from: tempDir, modelName: "OldModel")
            XCTFail("Expected loadModel to reject a pre-windowing pipelineVersion")
        } catch let error as ModelManager.ModelError {
            guard case .incompatiblePipelineVersion(let expected, let found) = error else {
                XCTFail("Expected incompatiblePipelineVersion, got \(error)")
                return
            }
            XCTAssertEqual(found, FeaturePipelineVersion.legacySingleWindow.versionHash)
            XCTAssertEqual(expected, FeaturePipelineVersion.current().versionHash)
        }
    }

    func testLoadModelAcceptsCurrentPipelineVersion() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadata = ModelMetadata(
            name: "NewModel",
            version: "1.0",
            pipelineVersion: FeaturePipelineVersion.current().versionHash,
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Genre"],
            tags: ["Genre": ["House"]],
            featureDimension: 1680
        )
        try metadata.save(to: tempDir.appendingPathComponent("NewModel.json"))

        let dummyModelDir = tempDir.appendingPathComponent("House.mlmodel")
        try FileManager.default.createDirectory(at: dummyModelDir, withIntermediateDirectories: true)

        let engine = try TaggingEngine()
        let (count, name) = try await engine.loadModel(from: tempDir, modelName: "NewModel")
        XCTAssertEqual(name, "NewModel")
        XCTAssertEqual(count, 0) // dummy model file loads no classifiers, but no version rejection
    }

    // MARK: - Per-category threshold defaults (Task 4.1)

    /// Loads an engine with metadata covering all four categories and an optional
    /// set of tuned per-tag thresholds. No real classifiers load (dummy model dir).
    private func makeEngineWithCategorizedModel(
        tagThresholds: [String: Float]? = nil
    ) async throws -> TaggingEngine {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadata = ModelMetadata(
            name: "ThresholdModel",
            version: "1.0",
            pipelineVersion: FeaturePipelineVersion.current().versionHash,
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Genre", "Timing", "Mood", "Descriptive"],
            tags: [
                "Genre": ["House", "Techno"],
                "Timing": ["Opener", "Late Night"],
                "Mood": ["Dark"],
                "Descriptive": ["Funky"]
            ],
            featureDimension: 1680,
            tagThresholds: tagThresholds
        )
        try metadata.save(to: tempDir.appendingPathComponent("ThresholdModel.json"))

        let dummyModelDir = tempDir.appendingPathComponent("House.mlmodel")
        try FileManager.default.createDirectory(at: dummyModelDir, withIntermediateDirectories: true)

        let engine = try TaggingEngine()
        _ = try await engine.loadModel(from: tempDir, modelName: "ThresholdModel")
        return engine
    }

    func testClassificationThresholdDefaultIsLowered() async throws {
        let engine = try TaggingEngine()
        let threshold = await engine.classificationThreshold
        XCTAssertEqual(threshold, 0.7, accuracy: 0.0001)
    }

    func testDefaultThresholdForCategory() async throws {
        let engine = try TaggingEngine()
        let genre = await engine.defaultThreshold(forCategory: "Genre")
        let mood = await engine.defaultThreshold(forCategory: "mood")
        let descriptive = await engine.defaultThreshold(forCategory: "Descriptive")
        let timing = await engine.defaultThreshold(forCategory: "Timing")
        let unknown = await engine.defaultThreshold(forCategory: "SomethingElse")
        let uncategorized = await engine.defaultThreshold(forCategory: nil)
        XCTAssertEqual(genre, 0.7, accuracy: 0.0001)
        XCTAssertEqual(mood, 0.55, accuracy: 0.0001)
        XCTAssertEqual(descriptive, 0.55, accuracy: 0.0001)
        XCTAssertEqual(timing, 0.55, accuracy: 0.0001)
        XCTAssertEqual(unknown, 0.7, accuracy: 0.0001)
        XCTAssertEqual(uncategorized, 0.7, accuracy: 0.0001)
    }

    func testThresholdResolvesToCategoryDefault() async throws {
        let engine = try await makeEngineWithCategorizedModel()
        let house = await engine.effectiveThreshold(forTag: "House")
        let dark = await engine.effectiveThreshold(forTag: "Dark")
        let funky = await engine.effectiveThreshold(forTag: "Funky")
        let opener = await engine.effectiveThreshold(forTag: "Opener")
        let mystery = await engine.effectiveThreshold(forTag: "Mystery")
        XCTAssertEqual(house, 0.7, accuracy: 0.0001, "Genre default should be 0.7")
        XCTAssertEqual(dark, 0.55, accuracy: 0.0001, "Mood default should be 0.55")
        XCTAssertEqual(funky, 0.55, accuracy: 0.0001, "Descriptive default should be 0.55")
        XCTAssertEqual(opener, 0.55, accuracy: 0.0001, "Timing default should be 0.55")
        XCTAssertEqual(mystery, 0.7, accuracy: 0.0001, "Uncategorized tag falls back to classificationThreshold")
    }

    func testTunedThresholdBeatsCategoryDefault() async throws {
        let engine = try await makeEngineWithCategorizedModel(tagThresholds: ["House": 0.42])
        let house = await engine.effectiveThreshold(forTag: "House")
        let dark = await engine.effectiveThreshold(forTag: "Dark")
        XCTAssertEqual(house, 0.42, accuracy: 0.0001, "Tuned per-tag threshold must win over category default")
        XCTAssertEqual(dark, 0.55, accuracy: 0.0001, "Untuned tags still get their category default")
    }

    func testStrictnessOffsetShiftsCategoryDefaults() async throws {
        let engine = try await makeEngineWithCategorizedModel(tagThresholds: ["House": 0.42])
        await engine.setStrictnessOffset(0.15)
        let dark = await engine.effectiveThreshold(forTag: "Dark")
        let opener = await engine.effectiveThreshold(forTag: "Opener")
        let techno = await engine.effectiveThreshold(forTag: "Techno")
        let house = await engine.effectiveThreshold(forTag: "House")
        XCTAssertEqual(dark, 0.70, accuracy: 0.0001, "Strict offset raises the Mood default by 0.15")
        XCTAssertEqual(opener, 0.70, accuracy: 0.0001, "Strict offset raises the Timing default by 0.15")
        XCTAssertEqual(techno, 0.85, accuracy: 0.0001, "Strict offset raises the Genre default by 0.15")
        XCTAssertEqual(house, 0.42, accuracy: 0.0001, "Tuned per-tag threshold still wins over the strictness offset")

        // Offsets clamp to [0.05, 0.99] — never an impossible threshold.
        await engine.setStrictnessOffset(0.50)
        let ceiling = await engine.effectiveThreshold(forTag: "Techno")
        XCTAssertEqual(ceiling, 0.99, accuracy: 0.0001, "Offset result clamps at 0.99")
        await engine.setStrictnessOffset(-0.60)
        let floor = await engine.effectiveThreshold(forTag: "Dark")
        XCTAssertEqual(floor, 0.05, accuracy: 0.0001, "Offset result clamps at 0.05")
    }

    func testAverageStrictnessPreservesCategoryStructure() async throws {
        let engine = try await makeEngineWithCategorizedModel()
        // Average strictness (offset 0) keeps the per-category structure intact.
        await engine.setStrictnessOffset(0.0)
        let genreDefault = await engine.effectiveThreshold(forTag: "House")
        let moodDefault = await engine.effectiveThreshold(forTag: "Dark")
        XCTAssertEqual(genreDefault, 0.7, accuracy: 0.0001, "Average strictness preserves the Genre 0.7 default")
        XCTAssertEqual(moodDefault, 0.55, accuracy: 0.0001, "Average strictness preserves the Mood 0.55 default")
        // Strict raises BOTH by 0.15 — the structure shifts, never flattens.
        await engine.setStrictnessOffset(0.15)
        let genreStrict = await engine.effectiveThreshold(forTag: "House")
        let moodStrict = await engine.effectiveThreshold(forTag: "Dark")
        XCTAssertEqual(genreStrict, 0.85, accuracy: 0.0001)
        XCTAssertEqual(moodStrict, 0.70, accuracy: 0.0001)
        XCTAssertEqual(genreStrict - moodStrict, genreDefault - moodDefault, accuracy: 0.0001,
            "The Genre/Mood gap is identical at every strictness level")
    }

    // MARK: - Stem/name dual-key resolution (S2)

    func testMultiWordTimingTagResolvesViaSanitizedStem() async throws {
        // Binary classifiers are keyed by sanitized file stems ("Late_Night");
        // metadata and tag_thresholds.json use tag names ("Late Night").
        let engine = try await makeEngineWithCategorizedModel()
        let stemDefault = await engine.effectiveThreshold(forTag: "Late_Night")
        XCTAssertEqual(stemDefault, 0.55, accuracy: 0.0001,
            "Sanitized stem must resolve to the Timing category default, not the 0.7 fallback")

        // The stem must hit the judgment-stage partition too.
        let probs: [String: Float] = ["Late_Night": 0.99, "House": 0.95]
        let emitted = await engine.binaryThresholdPass(
            rawProbabilities: probs,
            adjustedProbabilities: probs,
            moodPredictions: [:],
            genrePredictions: [:],
            instrumentPredictions: [:])
        XCTAssertEqual(emitted, ["House"], "Stem-keyed Timing tag must not leak from the perception pass")

        // A tuned threshold stored under the tag name resolves for its stem.
        let tuned = try await makeEngineWithCategorizedModel(tagThresholds: ["Late Night": 0.42])
        let tunedStem = await tuned.effectiveThreshold(forTag: "Late_Night")
        XCTAssertEqual(tunedStem, 0.42, accuracy: 0.0001,
            "Tuned threshold keyed by tag name must win for the sanitized stem")
    }

    // MARK: - Multi-class partition guard (S3)

    func testMultiClassTimingClassNotEmittedByPerceptionPass() async throws {
        let engine = try await makeEngineWithCategorizedModel()
        func prediction(_ cls: String) -> MultiClassClassifier.Prediction {
            MultiClassClassifier.Prediction(
                groupName: "Energy",
                predictedClass: cls,
                confidence: 0.9,
                runnerUpConfidence: 0.1,
                classProbabilities: [cls: 0.9, "Other": 0.1])
        }
        let timingEmits = await engine.multiClassEmits(prediction("Opener"))
        XCTAssertFalse(timingEmits, "A multi-class winner that is a Timing tag belongs to Stage 2 — never emitted by perception")
        let genreEmits = await engine.multiClassEmits(prediction("House"))
        XCTAssertTrue(genreEmits, "Perception-stage winners that pass the gate still emit")
    }

    // MARK: - Zero-shot partition (S6)

    func testZeroShotPerceptionFilterExcludesJudgmentTags() async throws {
        let engine = try await makeEngineWithCategorizedModel()
        let filtered = await engine.zeroShotPerceptionFilter(["Opener", "House", "Late_Night", "Funky"])
        XCTAssertEqual(filtered, ["House", "Funky"],
            "Zero-shot never emits judgment-stage tags — by name or by stem")
    }

    // MARK: - Stage 2 judgment inference (Task 4.2)

    /// One Stage 2 training row with a deterministic schema. `seed` drives
    /// separability: high seed → Peak-like, low seed → not.
    private func makeJudgmentRow(seed: Float, labels: Set<String>, trackID: String) -> JudgmentRow {
        let vector = JudgmentFeatureVector(
            binaryConfidences: ["Dark": seed, "Driving": 1 - seed],
            groupProbabilities: ["BassType": ["Punchy": seed / 2, "Walking": 1 - seed / 2]],
            bpm: 120 + seed * 20,
            durationSeconds: 300
        )
        return (features: vector, labels: labels, trackID: trackID)
    }

    /// Trains a REAL `Peak_judgment.mlmodel` (separable rows, deterministic
    /// seeds) into a temp directory and writes metadata that either pairs it
    /// (stage1ModelVersion + judgmentColumnNames) or deliberately does not.
    /// Caller must remove the returned directory.
    private func makeJudgmentModelDirectory(
        stage1Version: String? = "stage1-v1",
        writeColumnNames: Bool = true,
        tagThresholds: [String: Float]? = nil
    ) async throws -> (dir: URL, schema: [String]) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var rows: [JudgmentRow] = []
        for i in 0..<20 {
            rows.append(makeJudgmentRow(seed: 0.8 + Float(i) * 0.01, labels: ["Peak"], trackID: "p\(i)"))
        }
        for i in 0..<20 {
            rows.append(makeJudgmentRow(seed: Float(i) * 0.01, labels: ["Build"], trackID: "n\(i)"))
        }

        let trainer = ModelTrainer()
        let (results, _, columnNames) = try await trainer.trainJudgmentModels(
            rows: rows,
            tags: ["Peak"],
            outputDirectory: tempDir,
            config: TrainingConfig(minSamplesPerTag: 10)
        )
        XCTAssertEqual(results.count, 1, "Fixture must train exactly the Peak judgment model")
        let schema = try XCTUnwrap(columnNames)

        let metadata = ModelMetadata(
            name: "JudgmentModel",
            version: "1.0",
            pipelineVersion: FeaturePipelineVersion.current().versionHash,
            trainedAt: Date(),
            trainingFileCount: 40,
            categories: ["Genre", "Timing", "Mood", "Descriptive"],
            tags: [
                "Genre": ["House"],
                "Timing": ["Peak"],
                "Mood": ["Dark"],
                "Descriptive": ["Driving"]
            ],
            featureDimension: 1680,
            tagThresholds: tagThresholds,
            stage1ModelVersion: stage1Version,
            judgmentColumnNames: writeColumnNames ? schema : nil
        )
        try metadata.save(to: tempDir.appendingPathComponent("JudgmentModel.json"))
        return (tempDir, schema)
    }

    private func loadEngine(from dir: URL) async throws -> TaggingEngine {
        let engine = try TaggingEngine()
        _ = try await engine.loadModel(from: dir, modelName: "JudgmentModel")
        return engine
    }

    func testJudgmentModelsLoadWhenMetadataPairs() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        let loaded = await engine.loadedJudgmentTags
        XCTAssertEqual(loaded, ["Peak"], "Paired metadata must load the judgment classifier")
    }

    func testJudgmentModelsRefusedWithoutStage1Version() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory(stage1Version: nil)
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        let loaded = await engine.loadedJudgmentTags
        XCTAssertTrue(loaded.isEmpty, "Judgment models without a stage1ModelVersion pairing are stale — refuse")
        let pass = await engine.judgmentPass(
            binaryConfidences: ["Dark": 0.9, "Driving": 0.1],
            groupProbabilities: ["BassType": ["Punchy": 0.45, "Walking": 0.55]],
            bpm: 138, durationSeconds: 300)
        XCTAssertTrue(pass.tags.isEmpty)
        XCTAssertFalse(pass.judgmentAvailable)
    }

    func testJudgmentModelsRefusedWithoutJudgmentColumnNames() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory(writeColumnNames: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        let loaded = await engine.loadedJudgmentTags
        XCTAssertTrue(loaded.isEmpty, "No judgmentColumnNames in metadata → no schema to validate → refuse")
    }

    func testJudgmentPassEmitsTimingTagAboveThreshold() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        // Strongly Peak-like input (mirrors positive training rows)
        let pass = await engine.judgmentPass(
            binaryConfidences: ["Dark": 0.95, "Driving": 0.05],
            groupProbabilities: ["BassType": ["Punchy": 0.475, "Walking": 0.525]],
            bpm: 139, durationSeconds: 300)
        XCTAssertTrue(pass.judgmentAvailable)
        XCTAssertEqual(pass.tags, ["Peak"], "Separable positive input must clear the Timing 0.55 threshold")
    }

    func testJudgmentPassNegativeInputEmitsNothingButStaysAvailable() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        let pass = await engine.judgmentPass(
            binaryConfidences: ["Dark": 0.05, "Driving": 0.95],
            groupProbabilities: ["BassType": ["Punchy": 0.025, "Walking": 0.975]],
            bpm: 121, durationSeconds: 300)
        XCTAssertTrue(pass.judgmentAvailable, "Judgment ran — a negative verdict is still a verdict")
        XCTAssertTrue(pass.tags.isEmpty)
    }

    func testJudgmentPassSchemaMismatchSkipsJudgment() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        // Missing the "Driving" binary column → constructed schema cannot
        // match metadata.judgmentColumnNames → skip, never garbage.
        let missing = await engine.judgmentPass(
            binaryConfidences: ["Dark": 0.95],
            groupProbabilities: ["BassType": ["Punchy": 0.475, "Walking": 0.525]],
            bpm: 139, durationSeconds: 300)
        XCTAssertTrue(missing.tags.isEmpty)
        XCTAssertFalse(missing.judgmentAvailable)

        // Extra unexpected column → same refusal.
        let extra = await engine.judgmentPass(
            binaryConfidences: ["Dark": 0.95, "Driving": 0.05, "Surprise": 0.5],
            groupProbabilities: ["BassType": ["Punchy": 0.475, "Walking": 0.525]],
            bpm: 139, durationSeconds: 300)
        XCTAssertTrue(extra.tags.isEmpty)
        XCTAssertFalse(extra.judgmentAvailable)
    }

    func testStaleTimingThresholdsDroppedWhenJudgmentActive() async throws {
        // Tuned Timing thresholds were optimized on legacy Stage-1 scores —
        // with Stage 2 active they must be dropped at load, not silently
        // applied to the new judgment confidences. Perception entries survive.
        let (dir, _) = try await makeJudgmentModelDirectory(
            tagThresholds: ["Peak": 0.42, "Dark": 0.48])
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        let peak = await engine.effectiveThreshold(forTag: "Peak")
        let dark = await engine.effectiveThreshold(forTag: "Dark")
        XCTAssertEqual(peak, 0.55, accuracy: 0.0001,
            "Stale tuned Timing threshold must fall back to the category default")
        XCTAssertEqual(dark, 0.48, accuracy: 0.0001,
            "Tuned perception-stage thresholds survive the drop")
    }

    func testJudgmentPassUnavailableWithoutJudgmentModels() async throws {
        let engine = try TaggingEngine()
        let pass = await engine.judgmentPass(
            binaryConfidences: ["Dark": 0.95],
            groupProbabilities: [:],
            bpm: nil, durationSeconds: nil)
        XCTAssertTrue(pass.tags.isEmpty)
        XCTAssertFalse(pass.judgmentAvailable)
    }

    func testTimingTagNeverEmittedByBinaryThresholdPass() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        // Even a 0.99-confidence Timing tag must not leak out of Stage 1.
        let probabilities: [String: Float] = ["Peak": 0.99, "House": 0.95]
        let emitted = await engine.binaryThresholdPass(
            rawProbabilities: probabilities,
            adjustedProbabilities: probabilities,
            moodPredictions: [:],
            genrePredictions: [:],
            instrumentPredictions: [:])
        XCTAssertEqual(emitted, ["House"], "Timing tags are Stage 2's exclusive domain")
    }

    func testFallbackMappingsExcludeJudgmentStageTags() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        await engine.setFallbackConfig(FallbackMappingConfig(
            mappings: [
                TagFallbackMapping(userTag: "Peak", essentiaSource: .mood, essentiaLabels: ["energetic"]),
                TagFallbackMapping(userTag: "Funky", essentiaSource: .mood, essentiaLabels: ["fun"])
            ],
            enabled: true
        ))
        let predictions = await engine.applyFallbackMappings(
            moodPredictions: ["energetic": 0.99, "fun": 0.99],
            genrePredictions: [:],
            instrumentPredictions: [:],
            excludingTrained: [])
        XCTAssertFalse(predictions.contains("Peak"), "Fallback must never emit a judgment-stage tag")
        XCTAssertTrue(predictions.contains("Funky"))
    }

    func testCooccurrenceBoostingDefaultsOff() async throws {
        let engine = try TaggingEngine()
        let boosting = await engine.useCooccurrenceBoosting
        XCTAssertFalse(boosting, "Stage 2 subsumes co-occurrence boosting; off by default pending eval")
    }

    func testBoosterInputScopedToPerceptionStage() async throws {
        let (dir, _) = try await makeJudgmentModelDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        let scoped = await engine.boosterInputProbabilities(
            ["Peak": 0.9, "House": 0.8, "Dark": 0.7])
        XCTAssertEqual(Set(scoped.keys), ["House", "Dark"],
            "Booster sees perception-stage probabilities only")
    }

    func testMultiClassPredictionRunnerUp() {
        let runnerUp = MultiClassClassifier.runnerUpConfidence(
            in: ["A": 0.5, "B": 0.3, "C": 0.2], excluding: "A")
        XCTAssertEqual(runnerUp, 0.3, accuracy: 0.0001)
        let single = MultiClassClassifier.runnerUpConfidence(in: ["A": 1.0], excluding: "A")
        XCTAssertEqual(single, 0, accuracy: 0.0001, "Single-class group has no runner-up")
    }

    func testMultiClassGateRequiresSeparationMargin() async throws {
        let engine = try await makeEngineWithCategorizedModel() // House: genre, threshold 0.7
        func prediction(_ confidence: Float, runnerUp: Float) -> MultiClassClassifier.Prediction {
            MultiClassClassifier.Prediction(
                groupName: "TestGroup",
                predictedClass: "House",
                confidence: confidence,
                runnerUpConfidence: runnerUp,
                classProbabilities: ["House": confidence, "Techno": runnerUp])
        }
        let flat = await engine.multiClassGatePasses(prediction(0.9, runnerUp: 0.8))
        XCTAssertFalse(flat, "0.10 separation < 0.15 margin — no forced answer on a flat spread")
        let separated = await engine.multiClassGatePasses(prediction(0.9, runnerUp: 0.6))
        XCTAssertTrue(separated)
        let belowThreshold = await engine.multiClassGatePasses(prediction(0.65, runnerUp: 0.1))
        XCTAssertFalse(belowThreshold, "Threshold still applies alongside the separation margin")
    }

    func testTimingPredictionSurfacedWhenJudgmentFires() async throws {
        // Paired-models fixture (same as testJudgmentPassEmitsTimingTagAboveThreshold).
        // The judgment pass must surface the argmax (label, calibrated confidence)
        // alongside its emitted tags so downstream callers (VibeGeneratorV2) can
        // reason about Stage 2's verdict without re-running inference.
        let (dir, _) = try await makeJudgmentModelDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = try await loadEngine(from: dir)
        let pass = await engine.judgmentPass(
            binaryConfidences: ["Dark": 0.95, "Driving": 0.05],
            groupProbabilities: ["BassType": ["Punchy": 0.475, "Walking": 0.525]],
            bpm: 139, durationSeconds: 300)
        XCTAssertTrue(pass.judgmentAvailable)
        let prediction = try XCTUnwrap(pass.timingPrediction,
            "Judgment fired — argmax (label, confidence) must surface")
        XCTAssertEqual(prediction.label, "Peak")
        XCTAssertGreaterThan(prediction.confidence, 0.5,
            "Separable positive input must carry > 0.5 calibrated confidence")
    }

    func testTimingPredictionNilWhenJudgmentUnavailable() async throws {
        // Engine loaded without judgment models — no Stage 2 verdict to surface.
        let engine = try TaggingEngine()
        let pass = await engine.judgmentPass(
            binaryConfidences: ["Dark": 0.95],
            groupProbabilities: [:],
            bpm: nil, durationSeconds: nil)
        XCTAssertFalse(pass.judgmentAvailable)
        XCTAssertNil(pass.timingPrediction,
            "No judgment pass → no honest Stage 2 prediction")
    }

    func testTaggingResultExposesTimingPredictionField() {
        let prediction = TimingPrediction(label: "Peak", confidence: 0.83)
        let result = TaggingResult(
            essentiaTags: EssentiaTags(genres: [], moods: [], instruments: []),
            embeddings: [],
            genreActivations: [],
            judgmentAvailable: true,
            timingPrediction: prediction)
        XCTAssertEqual(result.timingPrediction, prediction)
        XCTAssertTrue(result.judgmentAvailable)
    }

    func testTaggingResultTimingPredictionDefaultsNil() {
        // Backwards-compatible default: existing fixtures compile unchanged.
        let result = TaggingResult(
            essentiaTags: EssentiaTags(genres: [], moods: [], instruments: []),
            embeddings: [],
            genreActivations: [])
        XCTAssertNil(result.timingPrediction)
    }

    func testTaggingResultJudgmentAvailableDefaultsFalse() {
        let result = TaggingResult(
            essentiaTags: EssentiaTags(genres: [], moods: [], instruments: []),
            embeddings: [],
            genreActivations: [])
        XCTAssertFalse(result.judgmentAvailable,
            "Absent evidence of a judgment pass is honestly 'unavailable'")
    }

    func testLoadModelRejectsFeatureDimensionMismatch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 9999 maps to the default extractor config, whose real dimension can never be 9999,
        // so the engine's extractor cannot satisfy the model regardless of which models load.
        let metadata = ModelMetadata(
            name: "MismatchModel",
            version: "1.0",
            pipelineVersion: FeaturePipelineVersion.current().versionHash,
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Genre"],
            tags: ["Genre": ["House"]],
            featureDimension: 9999
        )
        try metadata.save(to: tempDir.appendingPathComponent("MismatchModel.json"))

        let dummyModelDir = tempDir.appendingPathComponent("House.mlmodel")
        try FileManager.default.createDirectory(at: dummyModelDir, withIntermediateDirectories: true)

        let engine = try TaggingEngine()
        do {
            _ = try await engine.loadModel(from: tempDir, modelName: "MismatchModel")
            XCTFail("Expected loadModel to reject a feature-dimension mismatch")
        } catch let error as ModelManager.ModelError {
            guard case .incompatiblePipelineVersion(let expected, _) = error else {
                XCTFail("Expected incompatiblePipelineVersion, got \(error)")
                return
            }
            XCTAssertTrue(expected.contains("9999"))
        }
    }
}
