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
}
