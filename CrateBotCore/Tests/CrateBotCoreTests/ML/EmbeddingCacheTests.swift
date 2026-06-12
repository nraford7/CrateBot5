import XCTest
@testable import CrateBotCore

final class EmbeddingCacheTests: XCTestCase {

    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbeddingCacheTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testCacheMissWhenFeatureConfigChanges() async {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP
        )
        let cache1 = EmbeddingCache(extractionConfig: config1)

        let testFile = tempDirectory.appendingPathComponent("test.mp3")
        try! "test".write(to: testFile, atomically: true, encoding: .utf8)

        let embeddings: [Float] = [1.0, 2.0, 3.0]
        await cache1.set(embeddings, for: testFile)

        let retrieved1 = await cache1.get(for: testFile)
        XCTAssertEqual(retrieved1, embeddings)

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetPlusGenres  // Different!
        )
        let cache2 = EmbeddingCache(extractionConfig: config2)

        let retrieved2 = await cache2.get(for: testFile)
        XCTAssertNil(retrieved2)
    }

    func testCacheMissWhenWindowDurationChanges() async {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            windowDuration: 15.0
        )
        let cache1 = EmbeddingCache(extractionConfig: config1)

        let testFile = tempDirectory.appendingPathComponent("test2.mp3")
        try! "test".write(to: testFile, atomically: true, encoding: .utf8)

        await cache1.set([1.0, 2.0], for: testFile)

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            windowDuration: 10.0  // Different duration
        )
        let cache2 = EmbeddingCache(extractionConfig: config2)

        let retrieved = await cache2.get(for: testFile)
        XCTAssertNil(retrieved)
    }

    func testCacheHitWithSameConfig() async {
        let config = FeatureExtractionConfig.default
        let cache = EmbeddingCache(extractionConfig: config)

        let testFile = tempDirectory.appendingPathComponent("test3.mp3")
        try! "test".write(to: testFile, atomically: true, encoding: .utf8)

        let embeddings: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]
        await cache.set(embeddings, for: testFile)

        let retrieved = await cache.get(for: testFile)
        XCTAssertEqual(retrieved, embeddings)
    }
}
