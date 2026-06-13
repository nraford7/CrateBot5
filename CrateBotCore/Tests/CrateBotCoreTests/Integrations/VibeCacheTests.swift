import XCTest
@testable import CrateBotCore

final class VibeCacheTests: XCTestCase {

    private var tempDir: URL!
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeCacheTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cacheURL = tempDir.appendingPathComponent("vibe_cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func sampleResult(short: String = "Late Night Groove") -> VibeGenerationResult {
        VibeGenerationResult(
            short: short,
            long: "sustained, low-lit, half-time feel",
            mixHint: "sits between Peak and Release"
        )
    }

    func testMissReturnsNil() async {
        let cache = VibeCache(cacheURL: cacheURL)
        let hit = await cache.get(trackPath: "/no/such/track.mp3", stage1ModelVersion: "v1")
        XCTAssertNil(hit)
    }

    func testSetThenGetReturnsValue() async {
        let cache = VibeCache(cacheURL: cacheURL)
        let result = sampleResult()
        await cache.set(result, trackPath: "/a.mp3", stage1ModelVersion: "v1")
        let hit = await cache.get(trackPath: "/a.mp3", stage1ModelVersion: "v1")
        XCTAssertEqual(hit, result)
        XCTAssertEqual(hit?.short, "Late Night Groove")
        XCTAssertEqual(hit?.long, "sustained, low-lit, half-time feel")
        XCTAssertEqual(hit?.mixHint, "sits between Peak and Release")
    }

    func testDifferentStage1VersionMisses() async {
        let cache = VibeCache(cacheURL: cacheURL)
        await cache.set(sampleResult(), trackPath: "/a.mp3", stage1ModelVersion: "v1")
        let same = await cache.get(trackPath: "/a.mp3", stage1ModelVersion: "v1")
        let bumped = await cache.get(trackPath: "/a.mp3", stage1ModelVersion: "v2")
        XCTAssertNotNil(same)
        XCTAssertNil(bumped)
    }

    func testPersistsAcrossInstances() async {
        let result = sampleResult(short: "Cross-Instance Vibe")
        let cacheA = VibeCache(cacheURL: cacheURL)
        await cacheA.set(result, trackPath: "/persistent.mp3", stage1ModelVersion: "v1")
        // Drop reference (no async close needed; atomic write happened during set).
        _ = cacheA

        let cacheB = VibeCache(cacheURL: cacheURL)
        let hit = await cacheB.get(trackPath: "/persistent.mp3", stage1ModelVersion: "v1")
        XCTAssertEqual(hit, result)
        let count = await cacheB.count()
        XCTAssertEqual(count, 1)
    }

    func testCorruptFileStartsEmpty() async {
        try? Data("not json at all".utf8).write(to: cacheURL, options: .atomic)
        let cache = VibeCache(cacheURL: cacheURL)
        let count = await cache.count()
        XCTAssertEqual(count, 0)
        let hit = await cache.get(trackPath: "/x.mp3", stage1ModelVersion: "v1")
        XCTAssertNil(hit)
    }
}
