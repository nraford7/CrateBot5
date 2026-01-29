# Training Pipeline Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix cache/checkpoint compatibility, wire TrainingConfiguration end-to-end, fix multi-class nondeterminism, and clarify SpecAugment naming.

**Architecture:** We'll add feature extraction parameters to cache keys and checkpoint metadata, then wire unused TrainingConfiguration fields through the training pipeline. Multi-class label assignment will be made deterministic by sorting tags. SpecAugment will be renamed to reflect its actual behavior (feature noise).

**Tech Stack:** Swift, XCTest, Swift Package Manager

---

## Task 1: Add FeatureExtractionConfig for Cache Key Versioning

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/FeatureExtractionConfig.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/FeatureExtractionConfigTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import CrateBotCore

final class FeatureExtractionConfigTests: XCTestCase {

    func testConfigHashIncludesAllParameters() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        // Same config should produce same hash
        XCTAssertEqual(config1.configHash, config2.configHash)
        XCTAssertFalse(config1.configHash.isEmpty)
    }

    func testConfigHashChangesWhenSegmentDurationChanges() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 20.0,  // Different duration
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testConfigHashChangesWhenFeatureConfigChanges() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetPlusGenres,  // Different feature config
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testConfigHashChangesWhenSegmentFractionsChange() {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.25, 0.5, 0.75]  // Different fractions
        )

        XCTAssertNotEqual(config1.configHash, config2.configHash)
    }

    func testDefaultConfig() {
        let config = FeatureExtractionConfig.default

        XCTAssertEqual(config.featureConfig, .effnetGenresCLAP)
        XCTAssertEqual(config.segmentDuration, 30.0)
        XCTAssertEqual(config.segmentStartFractions, [0.33, 0.5, 0.66])
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter FeatureExtractionConfigTests 2>&1 | head -20`
Expected: Compilation error - FeatureExtractionConfig not found

**Step 3: Write minimal implementation**

```swift
import Foundation
import CryptoKit

/// Configuration for feature extraction that affects cache compatibility.
/// Changes to any of these parameters require cache invalidation.
public struct FeatureExtractionConfig: Codable, Equatable, Sendable {
    /// Which feature extractors to use (EffNet only, +Genres, or +CLAP)
    public let featureConfig: CombinedFeatureExtractor.FeatureConfig

    /// Duration of each audio segment in seconds
    public let segmentDuration: Double

    /// Start positions as fractions of total track duration
    public let segmentStartFractions: [Double]

    public init(
        featureConfig: CombinedFeatureExtractor.FeatureConfig,
        segmentDuration: Double,
        segmentStartFractions: [Double]
    ) {
        self.featureConfig = featureConfig
        self.segmentDuration = segmentDuration
        self.segmentStartFractions = segmentStartFractions
    }

    /// Default configuration matching current TrainingDataCollector defaults
    public static let `default` = FeatureExtractionConfig(
        featureConfig: .effnetGenresCLAP,
        segmentDuration: 30.0,
        segmentStartFractions: [0.33, 0.5, 0.66]
    )

    /// Deterministic hash for cache key comparison
    public var configHash: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        guard let data = try? encoder.encode(self) else {
            return "invalid"
        }

        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// Make FeatureConfig Codable for hashing
extension CombinedFeatureExtractor.FeatureConfig: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "effnetOnly": self = .effnetOnly
        case "effnetPlusGenres": self = .effnetPlusGenres
        case "effnetGenresCLAP": self = .effnetGenresCLAP
        default: self = .effnetGenresCLAP
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .effnetOnly: try container.encode("effnetOnly")
        case .effnetPlusGenres: try container.encode("effnetPlusGenres")
        case .effnetGenresCLAP: try container.encode("effnetGenresCLAP")
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter FeatureExtractionConfigTests`
Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/FeatureExtractionConfig.swift CrateBotCore/Tests/CrateBotCoreTests/ML/FeatureExtractionConfigTests.swift
git commit -m "feat: add FeatureExtractionConfig for cache versioning

Captures featureConfig, segmentDuration, and segmentStartFractions
in a hashable struct. This hash will be used in cache keys to detect
when extraction parameters change.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Update EmbeddingCache to Use FeatureExtractionConfig in Cache Key

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/EmbeddingCache.swift`
- Test: Create `CrateBotCore/Tests/CrateBotCoreTests/ML/EmbeddingCacheTests.swift`

**Step 1: Write the failing test**

```swift
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
        // Create cache with one config
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )
        let cache1 = EmbeddingCache(extractionConfig: config1)

        // Create a test file
        let testFile = tempDirectory.appendingPathComponent("test.mp3")
        try! "test".write(to: testFile, atomically: true, encoding: .utf8)

        // Store embeddings
        let embeddings: [Float] = [1.0, 2.0, 3.0]
        await cache1.set(embeddings, for: testFile)

        // Verify we can retrieve with same config
        let retrieved1 = await cache1.get(for: testFile)
        XCTAssertEqual(retrieved1, embeddings)

        // Create cache with different config
        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetPlusGenres,  // Different!
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )
        let cache2 = EmbeddingCache(extractionConfig: config2)

        // Should miss because config changed
        let retrieved2 = await cache2.get(for: testFile)
        XCTAssertNil(retrieved2)
    }

    func testCacheMissWhenSegmentDurationChanges() async {
        let config1 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 30.0,
            segmentStartFractions: [0.33, 0.5, 0.66]
        )
        let cache1 = EmbeddingCache(extractionConfig: config1)

        let testFile = tempDirectory.appendingPathComponent("test2.mp3")
        try! "test".write(to: testFile, atomically: true, encoding: .utf8)

        await cache1.set([1.0, 2.0], for: testFile)

        let config2 = FeatureExtractionConfig(
            featureConfig: .effnetGenresCLAP,
            segmentDuration: 20.0,  // Different duration
            segmentStartFractions: [0.33, 0.5, 0.66]
        )
        let cache2 = EmbeddingCache(extractionConfig: config2)

        let retrieved = await cache2.get(for: testFile)
        XCTAssertNil(retrieved)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter EmbeddingCacheTests 2>&1 | head -30`
Expected: Compilation error - EmbeddingCache init doesn't accept extractionConfig

**Step 3: Modify EmbeddingCache**

Update `EmbeddingCache.swift` to:

1. Change the initializer to accept `FeatureExtractionConfig`
2. Store the config hash in cache entries
3. Validate config hash on retrieval

```swift
import Foundation
import os.log

/// Persistent cache for audio embeddings to avoid re-extracting features for unchanged files.
/// Embeddings are keyed by file path, modification date, AND extraction config hash,
/// so changed files or changed extraction parameters get re-extracted.
public actor EmbeddingCache {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "EmbeddingCache")

    /// Cache entry containing embeddings and metadata
    private struct CacheEntry: Codable {
        let embeddings: [Float]
        let modificationDate: Date
        let extractorVersion: String
        let configHash: String  // NEW: extraction config hash
    }

    /// In-memory cache (loaded from disk on init)
    private var cache: [String: CacheEntry] = [:]

    /// Whether cache has been modified since last save
    private var isDirty = false

    /// Cache file URL
    private let cacheURL: URL

    /// Current extractor version (cache invalidates if version changes)
    private let extractorVersion: String

    /// Current extraction config hash
    private let configHash: String

    /// Statistics
    private var hits = 0
    private var misses = 0

    // MARK: - Initialization

    public init(
        extractionConfig: FeatureExtractionConfig = .default,
        extractorVersion: String = "effnet-v2-extended-2192"
    ) {
        self.extractorVersion = extractorVersion
        self.configHash = extractionConfig.configHash

        // Store cache in Application Support/CrateBot/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cratebotDir = appSupport.appendingPathComponent("CrateBot")
        try? FileManager.default.createDirectory(at: cratebotDir, withIntermediateDirectories: true)
        self.cacheURL = cratebotDir.appendingPathComponent("embedding_cache.json")

        // Load existing cache synchronously in init (cache is local to this actor)
        if FileManager.default.fileExists(atPath: cacheURL.path),
           let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let loaded = try? decoder.decode([String: CacheEntry].self, from: data) {
                self.cache = loaded
            }
        }
    }

    // MARK: - Public API

    /// Get cached embeddings for a file, if available and still valid
    /// - Parameter url: URL of the audio file
    /// - Returns: Cached embeddings if valid, nil otherwise
    public func get(for url: URL) -> [Float]? {
        let key = url.path

        guard let entry = cache[key] else {
            misses += 1
            return nil
        }

        // Check if file has been modified since caching
        guard let currentModDate = getModificationDate(for: url) else {
            misses += 1
            return nil
        }

        // Check modification date matches (within 1 second tolerance)
        let timeDiff = abs(entry.modificationDate.timeIntervalSince(currentModDate))
        guard timeDiff < 1.0 else {
            misses += 1
            logger.debug("Cache miss (modified): \(url.lastPathComponent)")
            return nil
        }

        // Check extractor version matches
        guard entry.extractorVersion == extractorVersion else {
            misses += 1
            logger.debug("Cache miss (version): \(url.lastPathComponent)")
            return nil
        }

        // Check extraction config hash matches
        guard entry.configHash == configHash else {
            misses += 1
            logger.debug("Cache miss (config): \(url.lastPathComponent)")
            return nil
        }

        hits += 1
        return entry.embeddings
    }

    /// Store embeddings for a file in the cache
    /// - Parameters:
    ///   - embeddings: The extracted embeddings
    ///   - url: URL of the audio file
    public func set(_ embeddings: [Float], for url: URL) {
        guard let modDate = getModificationDate(for: url) else {
            return
        }

        let entry = CacheEntry(
            embeddings: embeddings,
            modificationDate: modDate,
            extractorVersion: extractorVersion,
            configHash: configHash
        )

        cache[url.path] = entry
        isDirty = true
    }

    /// Save cache to disk if modified
    public func saveIfNeeded() {
        guard isDirty else { return }
        saveToDisk()
    }

    /// Force save cache to disk
    public func save() {
        saveToDisk()
    }

    /// Clear all cached embeddings
    public func clear() {
        cache.removeAll()
        isDirty = true
        saveToDisk()
        logger.info("Embedding cache cleared")
    }

    /// Get cache statistics
    public var statistics: (hits: Int, misses: Int, totalEntries: Int) {
        (hits, misses, cache.count)
    }

    /// Reset statistics counters
    public func resetStatistics() {
        hits = 0
        misses = 0
    }

    // MARK: - Private Helpers

    private func getModificationDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            logger.info("No existing embedding cache found")
            return
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = try decoder.decode([String: CacheEntry].self, from: data)
            logger.info("Loaded \(self.cache.count) cached embeddings")
        } catch {
            logger.error("Failed to load embedding cache: \(error.localizedDescription)")
            cache = [:]
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            isDirty = false
            logger.info("Saved \(self.cache.count) embeddings to cache")
        } catch {
            logger.error("Failed to save embedding cache: \(error.localizedDescription)")
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter EmbeddingCacheTests`
Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/EmbeddingCache.swift CrateBotCore/Tests/CrateBotCoreTests/ML/EmbeddingCacheTests.swift
git commit -m "feat: include extraction config in EmbeddingCache key

Cache entries now include configHash from FeatureExtractionConfig.
Changing segment duration, segment positions, or feature config
will correctly invalidate cached embeddings.

Fixes silent data corruption when training with changed parameters.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Update TrainingCheckpoint to Store Feature Extraction Config

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCheckpoint.swift`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCheckpointTests.swift`

**Step 1: Write the failing test**

Add to `TrainingCheckpointTests.swift`:

```swift
// MARK: - Feature Extraction Config Tests

func testCheckpointStoresFeatureExtractionConfig() {
    let config = FeatureExtractionConfig(
        featureConfig: .effnetGenresCLAP,
        segmentDuration: 30.0,
        segmentStartFractions: [0.33, 0.5, 0.66]
    )

    let tracks = [TaggedTrack(id: "track1", tags: ["House"])]

    let checkpoint = TrainingCheckpoint(
        modelName: "ConfigTest",
        sourceDirectories: [testDirectory],
        processedTracks: tracks,
        totalTracksDiscovered: 1,
        featureExtractionConfig: config
    )

    XCTAssertEqual(checkpoint.featureExtractionConfig, config)
    XCTAssertEqual(checkpoint.checkpointVersion, 3)  // Version bumped for config support
}

func testCheckpointIncompatibleWhenFeatureConfigChanges() throws {
    let config1 = FeatureExtractionConfig(
        featureConfig: .effnetGenresCLAP,
        segmentDuration: 30.0,
        segmentStartFractions: [0.33, 0.5, 0.66]
    )

    let tracks = [TaggedTrack(id: "track1", tags: ["House"])]

    let checkpoint = TrainingCheckpoint(
        modelName: "ConfigChangeTest",
        sourceDirectories: [testDirectory],
        processedTracks: tracks,
        totalTracksDiscovered: 1,
        featureExtractionConfig: config1
    )

    // Different feature config
    let config2 = FeatureExtractionConfig(
        featureConfig: .effnetPlusGenres,
        segmentDuration: 30.0,
        segmentStartFractions: [0.33, 0.5, 0.66]
    )

    let compatibility = checkpointManager.isCheckpointCompatible(
        checkpoint,
        sourceDirectories: [testDirectory],
        currentTracks: tracks,
        currentConfig: config2
    )

    XCTAssertFalse(compatibility.isCompatible)
    XCTAssertEqual(compatibility.reason, .featureConfigMismatch)
}

func testBackwardsCompatibilityWithV2Checkpoint() throws {
    // Simulate a v2 checkpoint (no featureExtractionConfig field)
    let v2JSON = """
    {
        "modelName": "LegacyModel",
        "createdAt": "2024-01-01T00:00:00Z",
        "sourceDirectories": ["/path/to/music"],
        "processedTracks": [{"id": "track1", "tags": ["House"]}],
        "totalTracksDiscovered": 10,
        "checkpointVersion": 2,
        "tagHash": "abc123"
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let checkpoint = try decoder.decode(
        TrainingCheckpoint.self,
        from: v2JSON.data(using: .utf8)!
    )

    XCTAssertEqual(checkpoint.modelName, "LegacyModel")
    XCTAssertEqual(checkpoint.checkpointVersion, 2)
    XCTAssertNil(checkpoint.featureExtractionConfig)  // v2 has no config
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter TrainingCheckpointTests 2>&1 | head -30`
Expected: Compilation error - TrainingCheckpoint init doesn't accept featureExtractionConfig

**Step 3: Update TrainingCheckpoint**

1. Add `featureExtractionConfig: FeatureExtractionConfig?` property
2. Update initializer to accept config
3. Bump checkpoint version to 3
4. Add backwards compatibility for v2 checkpoints
5. Update `CheckpointManager.isCheckpointCompatible` to check config
6. Add `.featureConfigMismatch` to `IncompatibilityReason`

```swift
// Add to IncompatibilityReason enum:
case featureConfigMismatch

// Add description:
case .featureConfigMismatch:
    return "Feature extraction configuration has changed since checkpoint was created"
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter TrainingCheckpointTests`
Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCheckpoint.swift CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCheckpointTests.swift
git commit -m "feat: store feature extraction config in checkpoints

Checkpoints now validate that the feature extraction configuration
(segment duration, segment positions, feature config) matches between
checkpoint creation and resume. Version bumped to 3.

Prevents resuming training with incompatible cached features.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Update TrainingDataCollector to Use FeatureExtractionConfig

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift`

**Step 1: Identify changes needed**

Replace hardcoded segment config with `FeatureExtractionConfig`:
- Lines 139-140: Replace `segmentDurationSeconds` and `segmentStartFractions` with `featureExtractionConfig`
- Update `EmbeddingCache` initialization to pass config
- Update checkpoint creation to pass config

**Step 2: Make the modifications**

```swift
// Replace lines 137-140:
// MARK: - Segment Sampling
// private let segmentDurationSeconds: Double = 30.0
// private let segmentStartFractions: [Double] = [0.33, 0.5, 0.66]

// With:
// MARK: - Feature Extraction Configuration

/// Configuration for feature extraction (segment sampling, feature config)
/// This affects cache compatibility - changing it invalidates cached embeddings
public var featureExtractionConfig: FeatureExtractionConfig = .default
```

Update the `embeddingCache` initialization in init:
```swift
public init(
    id3Manager: ID3Manager = ID3Manager(),
    audioAnalyzer: AudioAnalyzer = AudioAnalyzer(),
    featureExtractionConfig: FeatureExtractionConfig = .default
) {
    self.id3Manager = id3Manager
    self.audioAnalyzer = audioAnalyzer
    self.featureExtractionConfig = featureExtractionConfig
    self.embeddingCache = EmbeddingCache(extractionConfig: featureExtractionConfig)
}
```

Update segment loading in `extractFeatures` (around line 766-770):
```swift
let buffers = try await audioAnalyzer.loadAudioSegments(
    from: fileURL,
    targetSampleRate: EffNetExtractor.targetSampleRate,
    segmentDuration: featureExtractionConfig.segmentDuration,
    startFractions: featureExtractionConfig.segmentStartFractions
)
```

**Step 3: Run existing tests to verify no regressions**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter TrainingDataCollectorTests`
Expected: All tests pass

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift
git commit -m "refactor: use FeatureExtractionConfig in TrainingDataCollector

Replaces hardcoded segmentDurationSeconds and segmentStartFractions
with configurable FeatureExtractionConfig. EmbeddingCache now receives
the config for proper cache key generation.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Fix Multi-Class Label Nondeterminism

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/MultiClassTrainingDataGenerator.swift`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/ML/MultiClassTrainingDataGeneratorTests.swift`

**Step 1: Write the failing test**

Add to `MultiClassTrainingDataGeneratorTests.swift`:

```swift
func testDeterministicLabelAssignmentWithMultipleTags() {
    // Track with multiple tags in the same group
    // Should always pick the same one (alphabetically first)
    let tracks = [
        makeTrack(id: "multi1", tags: ["Walking", "Rolling"], features: [1.0, 2.0, 3.0]),
        makeTrack(id: "multi2", tags: ["Rolling", "Walking"], features: [4.0, 5.0, 6.0]),
    ]

    // Add enough samples to meet threshold
    var allTracks = tracks
    allTracks += makeTracks(forClass: "Walking", count: 25, idPrefix: "walk")
    allTracks += makeTracks(forClass: "Rolling", count: 25, idPrefix: "roll")

    // Run multiple times - should always produce same result
    var results: [String] = []
    for _ in 0..<10 {
        let result = generator.generateTrainingData(for: "BassType", from: allTracks)
        let multiTagSamples = result?.samples.filter { $0.trackId.starts(with: "multi") }
        let classes = multiTagSamples?.map { $0.className }.sorted()
        results.append(classes?.joined(separator: ",") ?? "")
    }

    // All runs should produce identical results
    XCTAssertEqual(Set(results).count, 1, "Label assignment should be deterministic")

    // Both multi-tag tracks should get "Rolling" (alphabetically first matching class)
    let result = generator.generateTrainingData(for: "BassType", from: allTracks)
    let multi1 = result?.samples.first { $0.trackId == "multi1" }
    let multi2 = result?.samples.first { $0.trackId == "multi2" }
    XCTAssertEqual(multi1?.className, multi2?.className)
}
```

**Step 2: Run test to verify it fails (or is flaky)**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter testDeterministicLabelAssignmentWithMultipleTags`
Expected: May pass or fail randomly due to Set iteration order

**Step 3: Fix the implementation**

Update `MultiClassTrainingDataGenerator.swift` around lines 47-52:

```swift
// Before:
for tag in track.tags {
    if let className = registry.normalizeTagToClass(tag, inGroup: groupName) {
        assignedClass = className
        break
    }
}

// After:
// Sort tags for deterministic assignment when track has multiple matching tags
for tag in track.tags.sorted() {
    if let className = registry.normalizeTagToClass(tag, inGroup: groupName) {
        assignedClass = className
        break
    }
}
```

**Step 4: Run test to verify it passes consistently**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter MultiClassTrainingDataGeneratorTests`
Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/MultiClassTrainingDataGenerator.swift CrateBotCore/Tests/CrateBotCoreTests/ML/MultiClassTrainingDataGeneratorTests.swift
git commit -m "fix: make multi-class label assignment deterministic

Sort track.tags before iterating to ensure consistent label assignment
when a track has multiple tags in the same group. Previously, Set
iteration order was nondeterministic.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Wire TrainingConfiguration Tree Parameters to ModelTrainer

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelTrainerTests.swift`

**Step 1: Write the failing test**

Add to `ModelTrainerTests.swift`:

```swift
func testTrainingConfigTreeParametersAreUsed() {
    // Verify TrainingConfig includes tree parameters
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

    // Should have sensible defaults
    XCTAssertEqual(config.treeMaxDepth, 6)
    XCTAssertEqual(config.treeIterations, 100)
    XCTAssertEqual(config.treeStepSize, 0.3, accuracy: 0.001)
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter testTrainingConfigTreeParametersAreUsed 2>&1 | head -20`
Expected: Compilation error - TrainingConfig doesn't have tree parameters

**Step 3: Update TrainingConfig and ModelTrainer**

Add to `TrainingConfig` struct in `ModelTrainer.swift`:

```swift
/// MLBoostedTreeClassifier max depth
public let treeMaxDepth: Int

/// MLBoostedTreeClassifier iterations
public let treeIterations: Int

/// MLBoostedTreeClassifier step size (learning rate)
public let treeStepSize: Double
```

Update init:
```swift
public init(
    validationSplit: Double = 0.2,
    minSamplesPerTag: Int = 50,
    maxNegativeRatio: Double = 3.0,
    randomSeed: Int = 42,
    mixupEnabled: Bool = true,
    mixupAlpha: Float = 0.4,
    mixupRatio: Float = 0.3,
    labelSmoothingEnabled: Bool = true,
    labelSmoothingFactor: Float = 0.1,
    contrastiveLearningEnabled: Bool = true,
    treeMaxDepth: Int = 6,
    treeIterations: Int = 100,
    treeStepSize: Double = 0.3
) {
    // ... existing assignments ...
    self.treeMaxDepth = treeMaxDepth
    self.treeIterations = treeIterations
    self.treeStepSize = treeStepSize
}
```

Update `trainModels` method (around line 283-292) to use config values:

```swift
// Before:
let classifier = try MLBoostedTreeClassifier(
    trainingData: trainingData,
    targetColumn: "label",
    parameters: MLBoostedTreeClassifier.ModelParameters(
        maxDepth: 6,
        maxIterations: 100,
        minLossReduction: 0.0,
        minChildWeight: 1.0,
        stepSize: 0.3
    )
)

// After:
let classifier = try MLBoostedTreeClassifier(
    trainingData: trainingData,
    targetColumn: "label",
    parameters: MLBoostedTreeClassifier.ModelParameters(
        maxDepth: config.treeMaxDepth,
        maxIterations: config.treeIterations,
        minLossReduction: 0.0,
        minChildWeight: 1.0,
        stepSize: config.treeStepSize
    )
)
```

Do the same for `trainMultiClassModel` (around line 589-599).

**Step 4: Run test to verify it passes**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter ModelTrainerTests`
Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift CrateBotCore/Tests/CrateBotCoreTests/ML/ModelTrainerTests.swift
git commit -m "feat: wire tree parameters from TrainingConfig to ModelTrainer

treeMaxDepth, treeIterations, and treeStepSize are now configurable
via TrainingConfig instead of being hardcoded. This allows UI settings
to actually affect training behavior.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Wire BinaryTrainingDataGenerator Parameters from Config

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/BinaryTrainingDataGeneratorTests.swift`

**Step 1: Write the failing test**

Add to `BinaryTrainingDataGeneratorTests.swift`:

```swift
func testGeneratorUsesCustomMinSamples() {
    let generator = BinaryTrainingDataGenerator(minPositiveExamples: 10, maxNegativeRatio: 2.0)

    // Create tracks with only 15 positives (would fail with default 50)
    var tracks: [TaggedTrack] = []
    for i in 0..<15 {
        tracks.append(TaggedTrack(id: "pos\(i)", tags: ["TestTag"], features: [Float(i)]))
    }
    for i in 0..<50 {
        tracks.append(TaggedTrack(id: "neg\(i)", tags: ["OtherTag"], features: [Float(i)]))
    }

    let result = generator.generateTrainingData(for: "TestTag", from: tracks)

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.positive.count, 15)
    // maxNegativeRatio of 2.0 means max 30 negatives
    XCTAssertEqual(result?.negative.count, 30)
}

func testGeneratorWithDefaultMinSamplesRejectsSmallDataset() {
    let generator = BinaryTrainingDataGenerator()

    // Only 15 positives - should fail with default minPositiveExamples of 50
    var tracks: [TaggedTrack] = []
    for i in 0..<15 {
        tracks.append(TaggedTrack(id: "pos\(i)", tags: ["TestTag"], features: [Float(i)]))
    }
    for i in 0..<50 {
        tracks.append(TaggedTrack(id: "neg\(i)", tags: ["OtherTag"], features: [Float(i)]))
    }

    let result = generator.generateTrainingData(for: "TestTag", from: tracks)

    XCTAssertNil(result)
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter testGeneratorUsesCustomMinSamples 2>&1 | head -20`
Expected: Compilation error - BinaryTrainingDataGenerator init doesn't accept parameters

**Step 3: Update BinaryTrainingDataGenerator**

```swift
/// Generates balanced training data for binary classifiers
public struct BinaryTrainingDataGenerator: Sendable {
    /// Minimum positive examples required to train a tag classifier
    public let minPositiveExamples: Int

    /// Maximum negative:positive ratio to prevent class imbalance
    public let maxNegativeRatio: Double

    public init(minPositiveExamples: Int = 50, maxNegativeRatio: Double = 3.0) {
        self.minPositiveExamples = minPositiveExamples
        self.maxNegativeRatio = maxNegativeRatio
    }

    /// Generate balanced positive/negative training sets for a specific tag
    public func generateTrainingData(
        for tagName: String,
        from tracks: [TaggedTrack]
    ) -> (positive: [TaggedTrack], negative: [TaggedTrack])? {
        let positive = tracks.filter { $0.tags.contains(tagName) }
        let negative = tracks.filter { !$0.tags.contains(tagName) }

        // Skip tags with insufficient positive data
        guard positive.count >= minPositiveExamples else {
            return nil
        }

        // Skip tags with no negative samples
        guard !negative.isEmpty else {
            return nil
        }

        // Balance negative samples
        let maxNegatives = Int(Double(positive.count) * maxNegativeRatio)
        let balancedNegative = Array(negative.shuffled().prefix(maxNegatives))

        return (positive, balancedNegative)
    }

    /// Get all viable tags (those with sufficient positive examples)
    public func viableTags(from tracks: [TaggedTrack]) -> [String: Int] {
        var tagCounts: [String: Int] = [:]

        for track in tracks {
            for tag in track.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        return tagCounts.filter { $0.value >= minPositiveExamples }
    }
}
```

**Step 4: Update ModelTrainer to pass config values**

In `ModelTrainer.swift`, update the init and `trainModels` method:

```swift
public actor ModelTrainer {
    private let logger = Logger(subsystem: "com.cratebot", category: "ModelTrainer")

    public init() {}

    // In trainModels, create generator with config values:
    let dataGenerator = BinaryTrainingDataGenerator(
        minPositiveExamples: config.minSamplesPerTag,
        maxNegativeRatio: config.maxNegativeRatio
    )
```

**Step 5: Run tests to verify they pass**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter BinaryTrainingDataGeneratorTests`
Expected: All tests pass

**Step 6: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift CrateBotCore/Tests/CrateBotCoreTests/BinaryTrainingDataGeneratorTests.swift
git commit -m "feat: make BinaryTrainingDataGenerator configurable

minPositiveExamples and maxNegativeRatio are now constructor parameters
instead of static constants. ModelTrainer passes TrainingConfig values.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Rename SpecAugment to FeatureNoise for Clarity

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingConfiguration.swift`
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift`
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/AudioAugmenter.swift`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingConfigurationTests.swift`

**Step 1: Understand current state**

- `TrainingConfiguration.enableSpecAugment` and `featureNoisePercent` exist but are confusingly named
- `TrainingDataCollector` uses `augConfig.specAugmentEnabled` to control feature noise
- The actual SpecAugment (time/frequency masking on spectrograms) is NOT implemented

**Step 2: Rename for clarity**

In `TrainingConfiguration.swift`:
```swift
// Rename:
// public var enableSpecAugment: Bool
// To:
/// Whether to add Gaussian noise to extracted features for regularization
public var enableFeatureNoise: Bool

// Keep featureNoisePercent but document it's used when enableFeatureNoise is true
```

In `AudioAugmenter.AugmentationConfig`:
```swift
// Rename specAugmentEnabled to featureNoiseEnabled
public var featureNoiseEnabled: Bool
```

In `TrainingDataCollector.swift` (around line 801-805):
```swift
// Before:
let augmentedFeatures = AudioAugmenter.augmentFeatures(
    averaged,
    addNoise: augConfig.specAugmentEnabled,
    noiseScale: 0.02
)

// After:
let augmentedFeatures = AudioAugmenter.augmentFeatures(
    averaged,
    addNoise: augConfig.featureNoiseEnabled,
    noiseScale: augConfig.featureNoiseScale
)
```

**Step 3: Wire featureNoisePercent through**

Add `featureNoiseScale` to `AudioAugmenter.AugmentationConfig` and use `TrainingConfiguration.featureNoisePercent` value.

**Step 4: Update tests**

```swift
func testFeatureNoiseConfiguration() {
    let config = TrainingConfiguration(
        enableFeatureNoise: true,
        featureNoisePercent: 0.05
    )

    XCTAssertTrue(config.enableFeatureNoise)
    XCTAssertEqual(config.featureNoisePercent, 0.05, accuracy: 0.001)
}
```

**Step 5: Run all tests**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test`
Expected: All tests pass

**Step 6: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingConfiguration.swift CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift CrateBotCore/Sources/CrateBotCore/ML/AudioAugmenter.swift CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingConfigurationTests.swift
git commit -m "refactor: rename enableSpecAugment to enableFeatureNoise

The setting controls Gaussian noise on extracted features, not actual
SpecAugment (time/frequency masking). Renaming clarifies behavior.

Also wires featureNoisePercent through to augmentation code.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Update TrainingCoordinator to Pass Config Through Pipeline

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`

**Step 1: Verify TrainingCoordinator passes config correctly**

The coordinator at lines 499-509 already creates a `TrainingConfig` from `TrainingConfiguration`. Verify it includes the new tree parameters.

**Step 2: Update to include tree parameters**

```swift
let trainingConfig = TrainingConfig(
    validationSplit: options.configuration.validationSplit,
    minSamplesPerTag: options.configuration.minSamplesPerTag,
    maxNegativeRatio: options.configuration.maxNegativeRatio,
    randomSeed: options.configuration.randomSeed,
    mixupEnabled: options.configuration.enableMixup,
    mixupAlpha: options.configuration.mixupAlpha,
    mixupRatio: options.configuration.mixupRatio,
    labelSmoothingEnabled: options.configuration.enableLabelSmoothing,
    labelSmoothingFactor: options.configuration.labelSmoothingFactor,
    contrastiveLearningEnabled: options.configuration.enableContrastiveLoss,
    treeMaxDepth: options.configuration.treeMaxDepth,
    treeIterations: options.configuration.treeIterations,
    treeStepSize: options.configuration.treeStepSize
)
```

**Step 3: Run integration tests**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter TrainingCoordinatorTests`
Expected: All tests pass

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift
git commit -m "feat: pass tree parameters through TrainingCoordinator

TrainingCoordinator now forwards treeMaxDepth, treeIterations, and
treeStepSize from TrainingConfiguration to TrainingConfig.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 10: Run Full Test Suite and Verify

**Step 1: Run all tests**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test`
Expected: All tests pass

**Step 2: Build the app**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && xcodebuild -scheme CrateBot -configuration Debug build 2>&1 | tail -20`
Expected: Build succeeds

**Step 3: Final commit for any fixups**

```bash
git status
# If any uncommitted changes:
git add -A
git commit -m "chore: fix any build/test issues from refactoring

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Summary of Changes

| Issue | Fix | Files Changed |
|-------|-----|---------------|
| Cache doesn't include segment/feature config | Added `FeatureExtractionConfig` with hash in cache key | EmbeddingCache, TrainingDataCollector, new FeatureExtractionConfig |
| Checkpoint doesn't validate feature config | Store and validate `FeatureExtractionConfig` in checkpoint | TrainingCheckpoint |
| Multi-class nondeterminism | Sort `track.tags` before iteration | MultiClassTrainingDataGenerator |
| Tree params not wired | Pass `treeMaxDepth/Iterations/StepSize` from config | ModelTrainer, TrainingCoordinator |
| minSamples/maxNegativeRatio static | Make `BinaryTrainingDataGenerator` configurable | BinaryTrainingDataGenerator, ModelTrainer |
| SpecAugment naming confusion | Rename to `enableFeatureNoise`, wire `featureNoisePercent` | TrainingConfiguration, TrainingDataCollector, AudioAugmenter |
