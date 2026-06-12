import XCTest
@testable import CrateBotCore

/// Deterministic Stage 1 mock: derives confidences from the first feature
/// value, so judgment rows are separable without CoreML.
private struct MockStage1Predictor: Stage1Predictor {
    func confidences(
        features: [Float]
    ) async throws -> (binary: [String: Float], groups: [String: [String: Float]]) {
        let seed = features.first ?? 0
        return (binary: ["Dark": seed], groups: [:])
    }
}

/// Predictor that fails on first use — simulates a crash at the very start
/// of Phase B, after the Phase A checkpoint marker has been written.
private struct CrashingPredictor: Stage1Predictor {
    struct SimulatedCrash: Error {}
    func confidences(
        features: [Float]
    ) async throws -> (binary: [String: Float], groups: [String: [String: Float]]) {
        throw SimulatedCrash()
    }
}

/// Two-phase training: Phase A (Stage 1 perception models) then Phase B
/// (Stage 2 judgment models), with a checkpoint phase marker between them.
///
/// Partial-failure points covered here:
/// - crash at the start of Phase B → resume goes straight into Phase B
///   without retraining Stage 1 (stage1ModelVersion survives unchanged)
/// - Stage 1 version drift between checkpoint and disk → Phase B refuses,
///   both stages retrain together (fresh pairing version)
final class TwoPhaseTrainingCoordinatorTests: XCTestCase {

    private var tempDir: URL!
    private var modelName: String!
    private let checkpointManager = CheckpointManager()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        modelName = "TwoPhaseTest-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? checkpointManager.delete(modelName: modelName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Fixtures

    /// 15 House tracks tagged Timing=Peak (high features) and 15 Techno
    /// tracks tagged Timing=Build (low features). Separable for both stages.
    private func makeTracks() -> [TaggedTrack] {
        var tracks: [TaggedTrack] = []
        for i in 0..<15 {
            tracks.append(TaggedTrack(
                id: "/music/house_\(i).mp3",
                tags: ["House", "Peak"],
                features: (0..<20).map { _ in Float.random(in: 0.7...1.0) },
                tagsByCategory: ["Genre": ["House"], "Timing": ["Peak"]]
            ))
            tracks.append(TaggedTrack(
                id: "/music/techno_\(i).mp3",
                tags: ["Techno", "Build"],
                features: (0..<20).map { _ in Float.random(in: 0.0...0.3) },
                tagsByCategory: ["Genre": ["Techno"], "Timing": ["Build"]]
            ))
        }
        return tracks
    }

    private func makeOptions() -> TrainingCoordinator.TrainingOptions {
        var configuration = TrainingConfiguration.default
        configuration.minSamplesPerTag = 10
        configuration.enableMixup = false
        configuration.enableFeatureNoise = false
        return TrainingCoordinator.TrainingOptions(
            modelName: modelName,
            tagsByCategory: ["Genre": ["House", "Techno"], "Timing": ["Peak", "Build"]],
            tagGroupRegistry: TagGroupRegistry(),  // no multi-class groups
            configuration: configuration
        )
    }

    private func metadataURL() -> URL {
        tempDir.appendingPathComponent("\(modelName!).json")
    }

    private func loadMetadata() throws -> ModelMetadata {
        try ModelMetadata.load(from: metadataURL())
    }

    private func modelExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(fileName).path)
    }

    // MARK: - Happy path

    func testTwoPhaseTrainsStage1ThenStage2WithPairedMetadata() async throws {
        let coordinator = TrainingCoordinator()

        let summary = try await coordinator.trainTwoPhase(
            tracks: makeTracks(),
            options: makeOptions(),
            outputDirectory: tempDir,
            predictorOverride: MockStage1Predictor(),
            bpmLookup: { _ in 128 },
            durationLookup: { _ in 300 }
        )

        // Stage 1: perception tags trained as binary models
        XCTAssertTrue(modelExists("House.mlmodel"))
        XCTAssertTrue(modelExists("Techno.mlmodel"))
        // Timing tags are Stage 2's exclusive domain — no binary models
        XCTAssertFalse(modelExists("Peak.mlmodel"),
            "Judgment-stage tags must not be trained as Stage 1 binary classifiers")
        XCTAssertFalse(modelExists("Build.mlmodel"))

        // Stage 2: one judgment model per Timing tag
        XCTAssertTrue(modelExists("Peak_judgment.mlmodel"))
        XCTAssertTrue(modelExists("Build_judgment.mlmodel"))

        // Paired metadata
        let metadata = try loadMetadata()
        XCTAssertNotNil(metadata.stage1ModelVersion)
        let columns = try XCTUnwrap(metadata.judgmentColumnNames)
        XCTAssertTrue(columns.contains("bpm"))
        XCTAssertTrue(columns.contains("duration"))

        // Checkpoint cleaned up after full success
        XCTAssertFalse(checkpointManager.hasCheckpoint(modelName: modelName))

        // Summary includes both stages
        XCTAssertTrue(summary.trainedTags.contains("Peak"))
        XCTAssertTrue(summary.trainedTags.contains("House"))
    }

    // MARK: - Interrupt and resume (crash between Phase A and Phase B)

    func testCrashAfterPhaseAResumesIntoPhaseBWithoutRetrainingStage1() async throws {
        let tracks = makeTracks()
        let options = makeOptions()

        // Run 1: Phase A completes, Phase B crashes on its first prediction.
        let coordinator1 = TrainingCoordinator()
        do {
            _ = try await coordinator1.trainTwoPhase(
                tracks: tracks,
                options: options,
                outputDirectory: tempDir,
                predictorOverride: CrashingPredictor(),
                bpmLookup: { _ in 128 },
                durationLookup: { _ in 300 }
            )
            XCTFail("Expected Phase B crash")
        } catch {
            // expected
        }

        // Partial-failure state: Stage 1 on disk, checkpoint marks Phase A done.
        XCTAssertTrue(modelExists("House.mlmodel"))
        XCTAssertFalse(modelExists("Peak_judgment.mlmodel"))
        let checkpoint = try XCTUnwrap(checkpointManager.load(modelName: modelName))
        guard case .phaseACompleted(let checkpointedVersion) = checkpoint.phase else {
            XCTFail("Checkpoint after Phase A must carry the phaseACompleted marker, got \(checkpoint.phase)")
            return
        }
        let phaseAVersion = try XCTUnwrap(try loadMetadata().stage1ModelVersion)
        XCTAssertEqual(checkpointedVersion, phaseAVersion)

        // Run 2: a NEW coordinator resumes. No predictor override — the
        // production Stage1Predictor loads the Phase A models from disk.
        let coordinator2 = TrainingCoordinator()
        _ = try await coordinator2.trainTwoPhase(
            tracks: tracks,
            options: options,
            outputDirectory: tempDir,
            bpmLookup: { _ in 128 },
            durationLookup: { _ in 300 }
        )

        // Recovery: Phase B ran against the SAME Stage 1 — no retrain.
        let finalMetadata = try loadMetadata()
        XCTAssertEqual(finalMetadata.stage1ModelVersion, phaseAVersion,
            "Resume must reuse the checkpointed Stage 1, not mint a new version (which would mean a retrain)")
        let columns = try XCTUnwrap(finalMetadata.judgmentColumnNames)
        XCTAssertTrue(columns.contains("bin_House"),
            "Resumed Phase B must build its schema from the on-disk Stage 1 models")
        XCTAssertTrue(modelExists("Peak_judgment.mlmodel"))
        XCTAssertTrue(modelExists("Build_judgment.mlmodel"))
        XCTAssertFalse(checkpointManager.hasCheckpoint(modelName: modelName),
            "Checkpoint must be deleted after the resumed run completes")
    }

    // MARK: - Pairing enforcement (Stage 1 drift)

    func testPhaseBRefusesDriftedStage1AndRetrainsBothStages() async throws {
        let tracks = makeTracks()
        let options = makeOptions()

        // Run 1: crash after Phase A.
        let coordinator1 = TrainingCoordinator()
        _ = try? await coordinator1.trainTwoPhase(
            tracks: tracks,
            options: options,
            outputDirectory: tempDir,
            predictorOverride: CrashingPredictor(),
            bpmLookup: { _ in 128 },
            durationLookup: { _ in 300 }
        )
        let checkpoint = try XCTUnwrap(checkpointManager.load(modelName: modelName))
        guard case .phaseACompleted(let checkpointedVersion) = checkpoint.phase else {
            XCTFail("Expected phaseACompleted marker")
            return
        }

        // Drift: Stage 1 metadata on disk no longer matches the checkpoint
        // (as if another run replaced the Stage 1 models).
        let original = try loadMetadata()
        let drifted = ModelMetadata(
            name: original.name,
            version: original.version,
            pipelineVersion: original.pipelineVersion,
            trainedAt: original.trainedAt,
            trainingFileCount: original.trainingFileCount,
            categories: original.categories,
            tags: original.tags,
            tagGroups: original.tagGroups,
            accuracy: original.accuracy,
            featureDimension: original.featureDimension,
            stage1ModelVersion: "drifted-version"
        )
        try drifted.save(to: metadataURL())

        // Run 2 must refuse to pair Stage 2 with the drifted Stage 1 and
        // instead retrain both stages together.
        let coordinator2 = TrainingCoordinator()
        _ = try await coordinator2.trainTwoPhase(
            tracks: tracks,
            options: options,
            outputDirectory: tempDir,
            predictorOverride: MockStage1Predictor(),
            bpmLookup: { _ in 128 },
            durationLookup: { _ in 300 }
        )

        let finalMetadata = try loadMetadata()
        XCTAssertNotEqual(finalMetadata.stage1ModelVersion, "drifted-version",
            "Stage 2 must never pair with a Stage 1 version it was not generated from")
        XCTAssertNotEqual(finalMetadata.stage1ModelVersion, checkpointedVersion,
            "A refused resume retrains Stage 1, minting a fresh pairing version")
        XCTAssertNotNil(finalMetadata.judgmentColumnNames)
        XCTAssertTrue(modelExists("Peak_judgment.mlmodel"))
        XCTAssertFalse(checkpointManager.hasCheckpoint(modelName: modelName))
    }

    // MARK: - Resume verifies model FILES, not just metadata version

    /// Metadata can survive while the .mlmodel files do not (partial delete,
    /// failed copy). A resume that trusts the version string alone would load
    /// ZERO Stage 1 classifiers and train judgment models on a crippled
    /// bpm+duration-only schema. The resume must verify the files load and,
    /// on mismatch, treat it as drift: delete the checkpoint, retrain both.
    func testResumeRefusesWhenStage1ModelFilesMissing() async throws {
        let tracks = makeTracks()
        let options = makeOptions()

        // Run 1: crash after Phase A — models, metadata, marker all on disk.
        let coordinator1 = TrainingCoordinator()
        _ = try? await coordinator1.trainTwoPhase(
            tracks: tracks,
            options: options,
            outputDirectory: tempDir,
            predictorOverride: CrashingPredictor(),
            bpmLookup: { _ in 128 },
            durationLookup: { _ in 300 }
        )
        let checkpoint = try XCTUnwrap(checkpointManager.load(modelName: modelName))
        guard case .phaseACompleted(let checkpointedVersion) = checkpoint.phase else {
            XCTFail("Expected phaseACompleted marker")
            return
        }

        // Sabotage: the model FILES vanish, metadata survives — version
        // strings still match, so only file verification can catch this.
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("House.mlmodel"))
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("Techno.mlmodel"))

        // Run 2: no predictor override — the production load path runs.
        let coordinator2 = TrainingCoordinator()
        _ = try await coordinator2.trainTwoPhase(
            tracks: tracks,
            options: options,
            outputDirectory: tempDir,
            bpmLookup: { _ in 128 },
            durationLookup: { _ in 300 }
        )

        let finalMetadata = try loadMetadata()
        XCTAssertNotEqual(finalMetadata.stage1ModelVersion, checkpointedVersion,
            "Missing Stage 1 model files must force a full retrain (fresh pairing version), never a blind resume")
        XCTAssertTrue(modelExists("House.mlmodel"), "Retrain must restore the Stage 1 models")
        let columns = try XCTUnwrap(finalMetadata.judgmentColumnNames)
        XCTAssertTrue(columns.contains("bin_House"),
            "Judgment schema must carry Stage 1 outputs — a blind resume would have produced bpm+duration only")
        XCTAssertTrue(modelExists("Peak_judgment.mlmodel"))
        XCTAssertFalse(checkpointManager.hasCheckpoint(modelName: modelName))
    }

    // MARK: - Resume through the PUBLIC train() entry point

    /// THE blocker regression (B1): after a Phase-B crash, calling the public
    /// `train()` again runs collection + feature extraction BEFORE
    /// trainTwoPhase reads the checkpoint — and extraction's own checkpoint
    /// saves used to demote the `.phaseACompleted` marker back to
    /// `.featureExtraction`, making Phase-B resume unreachable in production.
    /// This test drives the real pipeline: real MP3 files with ID3 tags, a
    /// pre-populated embedding cache (no audio decode), a new track arriving
    /// between crash and retry (so the extraction save path actually runs),
    /// and asserts Stage 1 is NOT retrained.
    func testTrainEntryPointResumesPhaseBAfterCrashWithoutRetrainingStage1() async throws {
        guard let exampleURL = Bundle.module.url(forResource: "example", withExtension: "mp3") else {
            throw XCTSkip("Example MP3 file not found in test bundle")
        }

        // Real library: 12 House/Peak + 12 Techno/Build MP3s with ID3 tags.
        let musicDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrateBotTrainResume_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: musicDir) }

        let id3Manager = ID3Manager()
        @Sendable func addTrack(name: String, genre: String, timing: String) async throws -> URL {
            let url = musicDir.appendingPathComponent("\(name).mp3")
            try FileManager.default.copyItem(at: exampleURL, to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try await id3Manager.writeTags(TagsToWrite(genre: genre, timing: timing), to: url)
            return url
        }
        for i in 0..<12 {
            _ = try await addTrack(name: "house_\(i)", genre: "House", timing: "Peak")
            _ = try await addTrack(name: "techno_\(i)", genre: "Techno", timing: "Build")
        }

        // Shared collector with a pre-populated embedding cache: every
        // feature request is a cache hit — no audio decode, no EffNet run.
        let extractionConfig = FeatureExtractionConfig(
            featureConfig: .effnetPlusGenres,
            windowDuration: 10.0,
            windowFractions: [0.2, 0.6],
            clapWindowFractions: [0.5]
        )
        let cache = EmbeddingCache(extractionConfig: extractionConfig)
        let collector = TrainingDataCollector(
            id3Manager: id3Manager,
            featureExtractionConfig: extractionConfig,
            embeddingCache: cache
        )
        let options = makeOptions()

        // train() writes to the standard models directory — clean up after.
        let modelsDir = try await ModelManager().modelsDirectory().appendingPathComponent(modelName)
        defer { try? FileManager.default.removeItem(at: modelsDir) }
        let liveMetadataURL = modelsDir.appendingPathComponent("\(modelName!).json")

        // Collect once to learn the canonical (standardized) track IDs, then
        // cache separable 20-dim features under exactly those IDs.
        let collection = await collector.collectTrainingData(from: [musicDir])
        XCTAssertEqual(collection.tracks.count, 24)
        var trainTracks: [TaggedTrack] = []
        for track in collection.tracks {
            let features: [Float] = track.tags.contains("House")
                ? (0..<20).map { _ in Float.random(in: 0.7...1.0) }
                : (0..<20).map { _ in Float.random(in: 0.0...0.3) }
            await cache.set(features, for: URL(fileURLWithPath: track.id))
            trainTracks.append(TaggedTrack(
                id: track.id, tags: track.tags,
                features: features, tagsByCategory: track.tagsByCategory
            ))
        }

        // Run 1: Phase A completes, Phase B crashes — the genuine post-crash
        // state lands under the SAME models directory train() resolves.
        let coordinator1 = TrainingCoordinator(dataCollector: collector, checkpointManager: checkpointManager)
        do {
            _ = try await coordinator1.trainTwoPhase(
                tracks: trainTracks,
                options: options,
                sourceDirectories: [musicDir],
                predictorOverride: CrashingPredictor(),
                bpmLookup: { _ in 128 },
                durationLookup: { _ in 300 }
            )
            XCTFail("Expected Phase B crash")
        } catch {
            // expected
        }

        let phaseAVersion = try XCTUnwrap(try ModelMetadata.load(from: liveMetadataURL).stage1ModelVersion)
        let checkpoint = try XCTUnwrap(checkpointManager.load(modelName: modelName))
        guard case .phaseACompleted = checkpoint.phase else {
            XCTFail("Expected phaseACompleted marker, got \(checkpoint.phase)")
            return
        }

        // A new track arrives between crash and retry: the retry must run
        // feature extraction for it — the exact path that used to clobber
        // the phase marker.
        let newURL = try await addTrack(name: "house_new", genre: "House", timing: "Peak")
        let newID = newURL.standardizedFileURL.path
        await cache.set((0..<20).map { _ in Float.random(in: 0.7...1.0) }, for: URL(fileURLWithPath: newID))

        // Skip (not vacuously pass) when the feature extractor cannot
        // initialize here: the retry path under test requires it.
        let probe = await collector.extractFeatures(for: [TaggedTrack(id: newID, tags: ["House"])])
        guard probe.first?.features != nil else {
            throw XCTSkip("Feature extractor unavailable in this environment (EffNet model missing?)")
        }

        let stage1ModelURL = modelsDir.appendingPathComponent("House.mlmodel")
        let mtimeBefore = try FileManager.default
            .attributesOfItem(atPath: stage1ModelURL.path)[.modificationDate] as? Date

        // Run 2: the PUBLIC entry point — collection, viability, checkpoint
        // merge, feature extraction, then two-phase training.
        let coordinator2 = TrainingCoordinator(dataCollector: collector, checkpointManager: checkpointManager)
        let summary = try await coordinator2.train(from: [musicDir], options: options)

        // Stage 1 must NOT have been retrained.
        let finalMetadata = try ModelMetadata.load(from: liveMetadataURL)
        XCTAssertEqual(finalMetadata.stage1ModelVersion, phaseAVersion,
            "train() after a Phase-B crash must resume into Phase B with the checkpointed Stage 1 — a new version means Stage 1 was retrained from scratch")
        let mtimeAfter = try FileManager.default
            .attributesOfItem(atPath: stage1ModelURL.path)[.modificationDate] as? Date
        XCTAssertEqual(mtimeBefore, mtimeAfter,
            "Stage 1 model files must be untouched by the resumed run")

        // The new track flowed through extraction (cache hit) — proof the
        // checkpoint-saving path actually executed before the resume.
        XCTAssertEqual(summary.tracksUsedForTraining, 25,
            "All 25 tracks (24 checkpointed + 1 new) must reach training")

        // Phase B completed against the on-disk Stage 1.
        let columns = try XCTUnwrap(finalMetadata.judgmentColumnNames)
        XCTAssertTrue(columns.contains("bin_House"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("Peak_judgment.mlmodel").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("Build_judgment.mlmodel").path))
        XCTAssertFalse(checkpointManager.hasCheckpoint(modelName: modelName))
    }
}
