import XCTest
@testable import CrateBotCore

final class TrainingDataCollectorTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization() async {
        let collector = TrainingDataCollector()
        // Should initialize without errors
        XCTAssertNotNil(collector)
    }

    func testInitializationWithCustomDependencies() async {
        let id3Manager = ID3Manager()
        let audioAnalyzer = AudioAnalyzer()

        // EffNetExtractor is now lazy-loaded internally, not passed to init
        let collector = TrainingDataCollector(
            id3Manager: id3Manager,
            audioAnalyzer: audioAnalyzer
        )

        XCTAssertNotNil(collector)
    }

    // MARK: - Empty Directory Tests

    func testEmptyDirectoryReturnsEmptyResult() async throws {
        let collector = TrainingDataCollector()

        // Create a temporary empty directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let result = await collector.collectTrainingData(from: [tempDir])

        XCTAssertEqual(result.tracks.count, 0)
        XCTAssertEqual(result.scannedCount, 0)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.errors.count, 0)
    }

    func testNonExistentDirectoryReturnsEmptyResult() async {
        let collector = TrainingDataCollector()

        let nonExistentDir = URL(fileURLWithPath: "/nonexistent/directory/path")
        let result = await collector.collectTrainingData(from: [nonExistentDir])

        XCTAssertEqual(result.tracks.count, 0)
        XCTAssertEqual(result.scannedCount, 0)
        XCTAssertEqual(result.errorCount, 0)
    }

    // MARK: - DiscoverTags Tests

    func testDiscoverTagsReturnsCorrectCounts() async {
        let collector = TrainingDataCollector()

        let tracks = [
            TaggedTrack(id: "track1", tags: ["House", "Energetic"]),
            TaggedTrack(id: "track2", tags: ["House", "Chill"]),
            TaggedTrack(id: "track3", tags: ["Techno", "Energetic"]),
            TaggedTrack(id: "track4", tags: ["House"]),
        ]

        let tagCounts = await collector.discoverTags(from: tracks)

        XCTAssertEqual(tagCounts["House"], 3)
        XCTAssertEqual(tagCounts["Energetic"], 2)
        XCTAssertEqual(tagCounts["Chill"], 1)
        XCTAssertEqual(tagCounts["Techno"], 1)
    }

    func testDiscoverTagsEmptyTracksReturnsEmptyDict() async {
        let collector = TrainingDataCollector()

        let tagCounts = await collector.discoverTags(from: [])

        XCTAssertTrue(tagCounts.isEmpty)
    }

    func testDiscoverTagsTracksWithNoTags() async {
        let collector = TrainingDataCollector()

        let tracks = [
            TaggedTrack(id: "track1", tags: Set<String>()),
            TaggedTrack(id: "track2", tags: Set<String>()),
        ]

        let tagCounts = await collector.discoverTags(from: tracks)

        XCTAssertTrue(tagCounts.isEmpty)
    }

    // MARK: - CollectionProgress Tests

    func testCollectionProgressFraction() {
        let progress1 = TrainingDataCollector.CollectionProgress(
            processed: 50,
            total: 100,
            currentFile: nil
        )
        XCTAssertEqual(progress1.fraction, 0.5, accuracy: 0.001)

        let progress2 = TrainingDataCollector.CollectionProgress(
            processed: 0,
            total: 100,
            currentFile: nil
        )
        XCTAssertEqual(progress2.fraction, 0.0, accuracy: 0.001)

        let progress3 = TrainingDataCollector.CollectionProgress(
            processed: 100,
            total: 100,
            currentFile: nil
        )
        XCTAssertEqual(progress3.fraction, 1.0, accuracy: 0.001)
    }

    func testCollectionProgressFractionZeroTotal() {
        let progress = TrainingDataCollector.CollectionProgress(
            processed: 0,
            total: 0,
            currentFile: nil
        )
        XCTAssertEqual(progress.fraction, 0.0, accuracy: 0.001)
    }

    // MARK: - CollectionResult Tests

    func testCollectionResultInit() {
        let error = TrainingDataCollector.CollectionError(
            url: URL(fileURLWithPath: "/test.mp3"),
            message: "Test error"
        )

        let result = TrainingDataCollector.CollectionResult(
            tracks: [TaggedTrack(id: "track1", tags: ["House"])],
            scannedCount: 5,
            errorCount: 1,
            errors: [error]
        )

        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.scannedCount, 5)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.errors.count, 1)
    }

    // MARK: - CollectionError Tests

    func testCollectionErrorInit() {
        let url = URL(fileURLWithPath: "/path/to/file.mp3")
        let error = TrainingDataCollector.CollectionError(
            url: url,
            message: "File could not be read"
        )

        XCTAssertEqual(error.url.path, "/path/to/file.mp3")
        XCTAssertEqual(error.message, "File could not be read")
    }

    // MARK: - ExtractFeatures Tests

    func testExtractFeaturesSkipsTracksWithExistingFeatures() async {
        let collector = TrainingDataCollector()

        let existingFeatures: [Float] = [1.0, 2.0, 3.0]
        let tracks = [
            TaggedTrack(id: "track1", tags: ["House"], features: existingFeatures),
        ]

        let result = await collector.extractFeatures(for: tracks)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].features, existingFeatures)
    }

    func testExtractFeaturesEmptyTracksReturnsEmpty() async {
        let collector = TrainingDataCollector()

        let result = await collector.extractFeatures(for: [])

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Progress Callback Tests

    func testCollectTrainingDataCallsProgressCallback() async throws {
        let collector = TrainingDataCollector()

        // Create a temporary empty directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Use actor to safely track progress callback
        actor ProgressTracker {
            var called = false
            func markCalled() { called = true }
            func wasCalled() -> Bool { called }
        }

        let tracker = ProgressTracker()
        let result = await collector.collectTrainingData(from: [tempDir]) { progress in
            await tracker.markCalled()
            XCTAssertEqual(progress.total, 0)
        }

        // Progress callback should be called even for empty directory (final update)
        let wasCalled = await tracker.wasCalled()
        XCTAssertTrue(wasCalled)
        XCTAssertEqual(result.tracks.count, 0)
    }
}
