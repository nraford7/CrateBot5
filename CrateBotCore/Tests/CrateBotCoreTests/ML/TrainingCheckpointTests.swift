import XCTest
@testable import CrateBotCore

final class TrainingCheckpointTests: XCTestCase {

    // MARK: - Test Helpers

    private var testDirectory: URL!
    private var checkpointManager: CheckpointManager!

    override func setUp() async throws {
        try await super.setUp()
        checkpointManager = CheckpointManager()

        // Create a temporary test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrainingCheckpointTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        // Clean up test directory
        if let testDirectory = testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - TrainingCheckpoint Tests

    func testCheckpointCreation() {
        let tracks = [
            TaggedTrack(id: "/path/to/track1.mp3", tags: ["House", "Energetic"]),
            TaggedTrack(id: "/path/to/track2.mp3", tags: ["Techno"]),
        ]

        let checkpoint = TrainingCheckpoint(
            modelName: "TestModel",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 10
        )

        XCTAssertEqual(checkpoint.modelName, "TestModel")
        XCTAssertEqual(checkpoint.processedTracks.count, 2)
        XCTAssertEqual(checkpoint.totalTracksDiscovered, 10)
        XCTAssertEqual(checkpoint.checkpointVersion, 2)
        XCTAssertFalse(checkpoint.tagHash.isEmpty)
    }

    func testCheckpointTrackConversion() {
        let originalTrack = TaggedTrack(
            id: "/path/to/track.mp3",
            tags: ["House", "Chill"],
            features: [1.0, 2.0, 3.0]
        )

        let checkpointTrack = TrainingCheckpoint.CheckpointTrack(from: originalTrack)
        let convertedTrack = checkpointTrack.toTaggedTrack()

        XCTAssertEqual(convertedTrack.id, originalTrack.id)
        XCTAssertEqual(convertedTrack.tags, originalTrack.tags)
        XCTAssertEqual(convertedTrack.features, originalTrack.features)
    }

    func testGetTaggedTracks() {
        let tracks = [
            TaggedTrack(id: "track1", tags: ["House"], features: [1.0]),
            TaggedTrack(id: "track2", tags: ["Techno"], features: [2.0]),
        ]

        let checkpoint = TrainingCheckpoint(
            modelName: "TestModel",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 2
        )

        let retrievedTracks = checkpoint.getTaggedTracks()
        XCTAssertEqual(retrievedTracks.count, 2)
        XCTAssertEqual(retrievedTracks[0].id, "track1")
        XCTAssertEqual(retrievedTracks[1].id, "track2")
    }

    func testGetProcessedTrackIDs() {
        let tracks = [
            TaggedTrack(id: "track1", tags: ["House"]),
            TaggedTrack(id: "track2", tags: ["Techno"]),
            TaggedTrack(id: "track3", tags: ["Ambient"]),
        ]

        let checkpoint = TrainingCheckpoint(
            modelName: "TestModel",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 3
        )

        let trackIDs = checkpoint.getProcessedTrackIDs()
        XCTAssertEqual(trackIDs.count, 3)
        XCTAssertTrue(trackIDs.contains("track1"))
        XCTAssertTrue(trackIDs.contains("track2"))
        XCTAssertTrue(trackIDs.contains("track3"))
    }

    // MARK: - Tag Hash Tests

    func testTagHashComputation() {
        let tracks = [
            TaggedTrack(id: "track1", tags: ["House", "Energetic"]),
            TaggedTrack(id: "track2", tags: ["Techno"]),
        ]

        let hash1 = TrainingCheckpoint.computeTagHash(from: tracks)
        let hash2 = TrainingCheckpoint.computeTagHash(from: tracks)

        // Same tracks should produce same hash
        XCTAssertEqual(hash1, hash2)
        XCTAssertFalse(hash1.isEmpty)
    }

    func testTagHashChangesWhenTagsChange() {
        let tracks1 = [
            TaggedTrack(id: "track1", tags: ["House"]),
        ]
        let tracks2 = [
            TaggedTrack(id: "track1", tags: ["Techno"]),  // Different tag
        ]

        let hash1 = TrainingCheckpoint.computeTagHash(from: tracks1)
        let hash2 = TrainingCheckpoint.computeTagHash(from: tracks2)

        // Different tags should produce different hash
        XCTAssertNotEqual(hash1, hash2)
    }

    func testTagHashIsOrderIndependent() {
        let tracks1 = [
            TaggedTrack(id: "track1", tags: ["House"]),
            TaggedTrack(id: "track2", tags: ["Techno"]),
        ]
        let tracks2 = [
            TaggedTrack(id: "track2", tags: ["Techno"]),
            TaggedTrack(id: "track1", tags: ["House"]),
        ]

        let hash1 = TrainingCheckpoint.computeTagHash(from: tracks1)
        let hash2 = TrainingCheckpoint.computeTagHash(from: tracks2)

        // Order shouldn't matter - sorted internally
        XCTAssertEqual(hash1, hash2)
    }

    func testTagHashTagOrderIndependent() {
        let tracks1 = [
            TaggedTrack(id: "track1", tags: ["House", "Energetic"]),
        ]
        let tracks2 = [
            TaggedTrack(id: "track1", tags: ["Energetic", "House"]),  // Same tags, different order
        ]

        let hash1 = TrainingCheckpoint.computeTagHash(from: tracks1)
        let hash2 = TrainingCheckpoint.computeTagHash(from: tracks2)

        // Tag order within a track shouldn't matter
        XCTAssertEqual(hash1, hash2)
    }

    // MARK: - CheckpointManager Save/Load Tests

    func testSaveAndLoadCheckpoint() throws {
        let tracks = [
            TaggedTrack(id: "track1", tags: ["House"], features: [1.0, 2.0, 3.0]),
            TaggedTrack(id: "track2", tags: ["Techno"], features: [4.0, 5.0, 6.0]),
        ]

        let checkpoint = TrainingCheckpoint(
            modelName: "SaveLoadTest",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 10
        )

        // Save checkpoint
        try checkpointManager.save(checkpoint)

        // Load checkpoint
        let loaded = checkpointManager.load(modelName: "SaveLoadTest")
        XCTAssertNotNil(loaded)

        XCTAssertEqual(loaded?.modelName, "SaveLoadTest")
        XCTAssertEqual(loaded?.processedTracks.count, 2)
        XCTAssertEqual(loaded?.totalTracksDiscovered, 10)
        XCTAssertEqual(loaded?.tagHash, checkpoint.tagHash)

        // Clean up
        try checkpointManager.delete(modelName: "SaveLoadTest")
    }

    func testLoadNonExistentCheckpoint() {
        let loaded = checkpointManager.load(modelName: "NonExistentModel")
        XCTAssertNil(loaded)
    }

    func testHasCheckpoint() throws {
        let tracks = [TaggedTrack(id: "track1", tags: ["House"])]

        let checkpoint = TrainingCheckpoint(
            modelName: "HasCheckpointTest",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 1
        )

        XCTAssertFalse(checkpointManager.hasCheckpoint(modelName: "HasCheckpointTest"))

        try checkpointManager.save(checkpoint)
        XCTAssertTrue(checkpointManager.hasCheckpoint(modelName: "HasCheckpointTest"))

        try checkpointManager.delete(modelName: "HasCheckpointTest")
        XCTAssertFalse(checkpointManager.hasCheckpoint(modelName: "HasCheckpointTest"))
    }

    func testDeleteCheckpoint() throws {
        let tracks = [TaggedTrack(id: "track1", tags: ["House"])]

        let checkpoint = TrainingCheckpoint(
            modelName: "DeleteTest",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 1
        )

        try checkpointManager.save(checkpoint)
        XCTAssertTrue(checkpointManager.hasCheckpoint(modelName: "DeleteTest"))

        try checkpointManager.delete(modelName: "DeleteTest")
        XCTAssertFalse(checkpointManager.hasCheckpoint(modelName: "DeleteTest"))
    }

    // MARK: - Checkpoint Compatibility Tests

    func testCheckpointCompatibilityWithMatchingDirectories() throws {
        let tracks = [TaggedTrack(id: "track1", tags: ["House"])]

        let checkpoint = TrainingCheckpoint(
            modelName: "CompatTest",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 1
        )

        let compatibility = checkpointManager.isCheckpointCompatible(
            checkpoint,
            sourceDirectories: [testDirectory],
            currentTracks: tracks
        )

        XCTAssertTrue(compatibility.isCompatible)
        XCTAssertNil(compatibility.reason)
    }

    func testCheckpointIncompatibleWithDifferentDirectories() throws {
        let tracks = [TaggedTrack(id: "track1", tags: ["House"])]

        let checkpoint = TrainingCheckpoint(
            modelName: "IncompatDirTest",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 1
        )

        let differentDir = testDirectory.appendingPathComponent("different")
        let compatibility = checkpointManager.isCheckpointCompatible(
            checkpoint,
            sourceDirectories: [differentDir],
            currentTracks: tracks
        )

        XCTAssertFalse(compatibility.isCompatible)
        XCTAssertEqual(compatibility.reason, .sourceDirectoriesMismatch)
    }

    func testCheckpointIncompatibleWhenTagsModified() throws {
        let originalTracks = [
            TaggedTrack(id: "track1", tags: ["House"]),
        ]

        let checkpoint = TrainingCheckpoint(
            modelName: "TagModifiedTest",
            sourceDirectories: [testDirectory],
            processedTracks: originalTracks,
            totalTracksDiscovered: 1
        )

        // Current tracks have different tags
        let modifiedTracks = [
            TaggedTrack(id: "track1", tags: ["Techno"]),  // Tag changed!
        ]

        let compatibility = checkpointManager.isCheckpointCompatible(
            checkpoint,
            sourceDirectories: [testDirectory],
            currentTracks: modifiedTracks
        )

        XCTAssertFalse(compatibility.isCompatible)
        XCTAssertEqual(compatibility.reason, .tagsModified)
    }

    func testCheckpointCompatibleWhenTagsUnchanged() throws {
        let tracks = [
            TaggedTrack(id: "track1", tags: ["House", "Energetic"]),
            TaggedTrack(id: "track2", tags: ["Techno"]),
        ]

        let checkpoint = TrainingCheckpoint(
            modelName: "TagUnchangedTest",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 2
        )

        // Same tracks, same tags
        let compatibility = checkpointManager.isCheckpointCompatible(
            checkpoint,
            sourceDirectories: [testDirectory],
            currentTracks: tracks
        )

        XCTAssertTrue(compatibility.isCompatible)
        XCTAssertNil(compatibility.reason)
    }

    func testCheckpointCompatibilityWithoutCurrentTracks() throws {
        let tracks = [TaggedTrack(id: "track1", tags: ["House"])]

        let checkpoint = TrainingCheckpoint(
            modelName: "NoCurrentTracksTest",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 1
        )

        // When currentTracks is nil, only directories are checked
        let compatibility = checkpointManager.isCheckpointCompatible(
            checkpoint,
            sourceDirectories: [testDirectory],
            currentTracks: nil
        )

        XCTAssertTrue(compatibility.isCompatible)
    }

    // MARK: - Checkpoint Encoding/Decoding Tests

    func testCheckpointEncodingAndDecoding() throws {
        let tracks = [
            TaggedTrack(id: "track1", tags: ["House", "Energetic"], features: [1.0, 2.0]),
            TaggedTrack(id: "track2", tags: ["Techno"], features: nil),
        ]

        let original = TrainingCheckpoint(
            modelName: "EncodingTest",
            sourceDirectories: [testDirectory],
            processedTracks: tracks,
            totalTracksDiscovered: 5
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TrainingCheckpoint.self, from: data)

        XCTAssertEqual(decoded.modelName, original.modelName)
        XCTAssertEqual(decoded.processedTracks.count, original.processedTracks.count)
        XCTAssertEqual(decoded.totalTracksDiscovered, original.totalTracksDiscovered)
        XCTAssertEqual(decoded.tagHash, original.tagHash)
        XCTAssertEqual(decoded.checkpointVersion, original.checkpointVersion)
    }

    func testBackwardsCompatibilityWithV1Checkpoint() throws {
        // Simulate a v1 checkpoint (no tagHash field)
        let v1JSON = """
        {
            "modelName": "LegacyModel",
            "createdAt": "2024-01-01T00:00:00Z",
            "sourceDirectories": ["/path/to/music"],
            "processedTracks": [{"id": "track1", "tags": ["House"]}],
            "totalTracksDiscovered": 10,
            "checkpointVersion": 1
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let checkpoint = try decoder.decode(
            TrainingCheckpoint.self,
            from: v1JSON.data(using: .utf8)!
        )

        XCTAssertEqual(checkpoint.modelName, "LegacyModel")
        XCTAssertEqual(checkpoint.checkpointVersion, 1)
        XCTAssertTrue(checkpoint.tagHash.isEmpty)  // v1 has no tag hash
    }

    // MARK: - IncompatibilityReason Tests

    func testIncompatibilityReasonDescriptions() {
        XCTAssertEqual(
            IncompatibilityReason.sourceDirectoriesMismatch.description,
            "Source directories have changed since checkpoint was created"
        )
        XCTAssertEqual(
            IncompatibilityReason.tagsModified.description,
            "Tags have been modified since checkpoint was created"
        )
    }

    // MARK: - CheckpointError Tests

    func testCheckpointErrorDescriptions() {
        XCTAssertEqual(
            CheckpointError.directoryAccessFailed.errorDescription,
            "Cannot access checkpoints directory"
        )
        XCTAssertEqual(
            CheckpointError.saveFailed(reason: "Disk full").errorDescription,
            "Failed to save checkpoint: Disk full"
        )
        XCTAssertEqual(
            CheckpointError.loadFailed(reason: "Corrupt file").errorDescription,
            "Failed to load checkpoint: Corrupt file"
        )
    }
}
