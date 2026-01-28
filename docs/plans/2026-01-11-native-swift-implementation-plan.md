---
status: COMPLETED
completed_date: 2026-01-28
notes: Native Swift implementation is complete. This plan is archived for historical reference.
---

# CrateBot Native Swift Rewrite - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS app using Swift/SwiftUI and CoreML that replaces the current Electron+Python architecture.

**Architecture:** Two apps (CrateBot + Model Lab) sharing a CrateBotCore Swift package. SwiftData for persistence, AVFoundation for audio, CoreML for ML inference, security-scoped bookmarks for sandboxed file access.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, CoreML, Create ML, AVFoundation, Accelerate (vDSP), Sparkle 2.x

**Worktree:** `/Users/noahraford/CrateBot4/.worktrees/native-swift-rewrite`

---

## Phase 1: Project Setup

### Task 1.1: Create Xcode Project Structure

**Files:**
- Create: `CrateBot.xcodeproj` (via Xcode)
- Create: `CrateBotCore/Package.swift`
- Create: `CrateBot/App/CrateBotApp.swift`
- Create: `CrateBot/App/CrateBot.entitlements`

**Step 1: Create the Xcode workspace and projects**

```bash
cd /Users/noahraford/CrateBot4/.worktrees/native-swift-rewrite

# Create directory structure
mkdir -p CrateBot/App
mkdir -p CrateBot/Views
mkdir -p CrateBot/ViewModels
mkdir -p CrateBot/Resources
mkdir -p CrateBotModelLab/App
mkdir -p CrateBotModelLab/Views
mkdir -p CrateBotCore/Sources/CrateBotCore/Audio
mkdir -p CrateBotCore/Sources/CrateBotCore/ML
mkdir -p CrateBotCore/Sources/CrateBotCore/Data
mkdir -p CrateBotCore/Sources/CrateBotCore/Tags
mkdir -p CrateBotCore/Sources/CrateBotCore/Integrations
mkdir -p CrateBotCore/Sources/CrateBotCore/Networking
mkdir -p CrateBotCore/Tests/CrateBotCoreTests
mkdir -p Models/Bundled
```

**Step 2: Create CrateBotCore Package.swift**

Create `CrateBotCore/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CrateBotCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CrateBotCore",
            targets: ["CrateBotCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CrateBotCore",
            dependencies: [],
            path: "Sources/CrateBotCore"
        ),
        .testTarget(
            name: "CrateBotCoreTests",
            dependencies: ["CrateBotCore"],
            path: "Tests/CrateBotCoreTests"
        ),
    ]
)
```

**Step 3: Create placeholder source file**

Create `CrateBotCore/Sources/CrateBotCore/CrateBotCore.swift`:

```swift
import Foundation

/// CrateBotCore - Shared library for CrateBot applications
public enum CrateBotCore {
    public static let version = "1.0.0"
}
```

**Step 4: Create placeholder test file**

Create `CrateBotCore/Tests/CrateBotCoreTests/CrateBotCoreTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class CrateBotCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(CrateBotCore.version, "1.0.0")
    }
}
```

**Step 5: Run tests to verify package builds**

```bash
cd CrateBotCore
swift test
```

Expected: All tests pass

**Step 6: Commit**

```bash
git add .
git commit -m "feat: create CrateBotCore Swift package structure

- Add Package.swift with macOS 14+ target
- Create directory structure for Audio, ML, Data, Tags modules
- Add placeholder source and test files"
```

---

### Task 1.2: Create Entitlements File

**Files:**
- Create: `CrateBot/App/CrateBot.entitlements`

**Step 1: Create entitlements file**

Create `CrateBot/App/CrateBot.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

**Step 2: Commit**

```bash
git add CrateBot/App/CrateBot.entitlements
git commit -m "feat: add sandbox entitlements for file access and networking"
```

---

## Phase 2: Data Layer

### Task 2.1: SwiftData Models

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Data/Models.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ModelsTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/ModelsTests.swift`:

```swift
import XCTest
import SwiftData
@testable import CrateBotCore

final class ModelsTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([CachedFeatures.self, TagOverride.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testCachedFeaturesCreation() throws {
        let features = CachedFeatures(
            audioHash: "abc123",
            compressedFeatures: Data([0x01, 0x02, 0x03]),
            pipelineVersion: "v1.0",
            featureCount: 512
        )

        context.insert(features)
        try context.save()

        let descriptor = FetchDescriptor<CachedFeatures>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.audioHash, "abc123")
        XCTAssertEqual(fetched.first?.featureCount, 512)
    }

    func testTagOverrideWithDefaults() throws {
        let override = TagOverride(audioHash: "xyz789")

        XCTAssertNil(override.genre)
        XCTAssertEqual(override.mood, [])
        XCTAssertNil(override.timing)
        XCTAssertEqual(override.descriptive, [])
    }

    func testTagOverrideWithValues() throws {
        let override = TagOverride(
            audioHash: "xyz789",
            genre: "House",
            mood: ["energetic", "uplifting"],
            timing: "Peak",
            descriptive: ["funky", "groovy"]
        )

        context.insert(override)
        try context.save()

        let descriptor = FetchDescriptor<TagOverride>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.first?.mood, ["energetic", "uplifting"])
        XCTAssertEqual(fetched.first?.descriptive, ["funky", "groovy"])
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter ModelsTests
```

Expected: FAIL - CachedFeatures and TagOverride not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/Data/Models.swift`:

```swift
import Foundation
import SwiftData

@Model
public class CachedFeatures {
    @Attribute(.unique) public var audioHash: String
    public var compressedFeatures: Data
    public var pipelineVersion: String
    public var featureCount: Int
    public var extractedAt: Date

    public init(
        audioHash: String,
        compressedFeatures: Data,
        pipelineVersion: String,
        featureCount: Int,
        extractedAt: Date = .now
    ) {
        self.audioHash = audioHash
        self.compressedFeatures = compressedFeatures
        self.pipelineVersion = pipelineVersion
        self.featureCount = featureCount
        self.extractedAt = extractedAt
    }
}

@Model
public class TagOverride {
    @Attribute(.unique) public var audioHash: String
    public var genre: String?
    public var mood: [String]
    public var timing: String?
    public var descriptive: [String]
    public var correctedAt: Date

    public init(
        audioHash: String,
        genre: String? = nil,
        mood: [String] = [],
        timing: String? = nil,
        descriptive: [String] = [],
        correctedAt: Date = .now
    ) {
        self.audioHash = audioHash
        self.genre = genre
        self.mood = mood
        self.timing = timing
        self.descriptive = descriptive
        self.correctedAt = correctedAt
    }
}

// MARK: - Schema Versioning

public enum CrateBotSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [CachedFeatures.self, TagOverride.self]
    }
}

public enum CrateBotMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CrateBotSchemaV1.self]
    }
    public static var stages: [MigrationStage] {
        []
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter ModelsTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Data/Models.swift
git add CrateBotCore/Tests/CrateBotCoreTests/ModelsTests.swift
git commit -m "feat: add SwiftData models for feature cache and tag overrides

- CachedFeatures with LZ4-compressed features and pipeline versioning
- TagOverride with explicit empty array defaults
- Schema versioning for future migrations"
```

---

### Task 2.2: Feature Pipeline Version

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Data/FeaturePipelineVersion.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/FeaturePipelineVersionTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/FeaturePipelineVersionTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class FeaturePipelineVersionTests: XCTestCase {
    func testVersionHashIsConsistent() {
        let version1 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1", "apple": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        let version2 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1", "apple": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        XCTAssertEqual(version1.versionHash, version2.versionHash)
    }

    func testVersionHashChangeOnExtractorUpdate() {
        let version1 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        let version2 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v2"],  // Changed
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        XCTAssertNotEqual(version1.versionHash, version2.versionHash)
    }

    func testVersionHashChangeOnNormalizationChange() {
        let version1 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "zscore", perFeature: true, clipMin: -3, clipMax: 3)
        )

        let version2 = FeaturePipelineVersion(
            extractorVersions: ["spectral": "v1"],
            windowingParams: .init(windowSize: 2048, hopSize: 512, fftSize: 2048),
            normalizationParams: .init(method: "minmax", perFeature: true, clipMin: 0, clipMax: 1)  // Changed
        )

        XCTAssertNotEqual(version1.versionHash, version2.versionHash)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter FeaturePipelineVersionTests
```

Expected: FAIL - FeaturePipelineVersion not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/Data/FeaturePipelineVersion.swift`:

```swift
import Foundation
import CryptoKit

public struct FeaturePipelineVersion: Codable, Equatable, Sendable {
    public let extractorVersions: [String: String]
    public let windowingParams: WindowingParams
    public let normalizationParams: NormalizationParams

    public struct WindowingParams: Codable, Equatable, Sendable {
        public let windowSize: Int
        public let hopSize: Int
        public let fftSize: Int

        public init(windowSize: Int, hopSize: Int, fftSize: Int) {
            self.windowSize = windowSize
            self.hopSize = hopSize
            self.fftSize = fftSize
        }
    }

    public struct NormalizationParams: Codable, Equatable, Sendable {
        public let method: String
        public let perFeature: Bool
        public let clipMin: Float?
        public let clipMax: Float?

        public init(method: String, perFeature: Bool, clipMin: Float? = nil, clipMax: Float? = nil) {
            self.method = method
            self.perFeature = perFeature
            self.clipMin = clipMin
            self.clipMax = clipMax
        }
    }

    public init(
        extractorVersions: [String: String],
        windowingParams: WindowingParams,
        normalizationParams: NormalizationParams
    ) {
        self.extractorVersions = extractorVersions
        self.windowingParams = windowingParams
        self.normalizationParams = normalizationParams
    }

    /// Deterministic hash for cache key comparison
    public var versionHash: String {
        // Sort keys for deterministic encoding
        let sortedExtractors = extractorVersions.sorted { $0.key < $1.key }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        struct HashableVersion: Encodable {
            let extractors: [(String, String)]
            let windowing: WindowingParams
            let normalization: NormalizationParams

            enum CodingKeys: String, CodingKey {
                case extractors, windowing, normalization
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Dictionary(uniqueKeysWithValues: extractors), forKey: .extractors)
                try container.encode(windowing, forKey: .windowing)
                try container.encode(normalization, forKey: .normalization)
            }
        }

        let hashable = HashableVersion(
            extractors: sortedExtractors,
            windowing: windowingParams,
            normalization: normalizationParams
        )

        guard let data = try? encoder.encode(hashable) else {
            return "invalid"
        }

        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter FeaturePipelineVersionTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Data/FeaturePipelineVersion.swift
git add CrateBotCore/Tests/CrateBotCoreTests/FeaturePipelineVersionTests.swift
git commit -m "feat: add FeaturePipelineVersion for cache invalidation

- Captures extractor versions, windowing params, normalization params
- Deterministic SHA256 hash for cache key comparison
- Changes to any parameter invalidate cached features"
```

---

### Task 2.3: Feature Compression Utilities

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Data/FeatureCompression.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/FeatureCompressionTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/FeatureCompressionTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class FeatureCompressionTests: XCTestCase {
    func testRoundTrip() throws {
        let original: [Float] = [1.0, 2.5, -3.7, 0.0, 100.123]

        let compressed = original.toCompressedData()
        let decompressed = try [Float].fromCompressedData(compressed)

        XCTAssertEqual(original, decompressed)
    }

    func testCompressionReducesSize() throws {
        // Create a large array with repeating patterns (compresses well)
        let original = [Float](repeating: 1.0, count: 10000)

        let uncompressedSize = original.count * MemoryLayout<Float>.size
        let compressed = original.toCompressedData()

        XCTAssertLessThan(compressed.count, uncompressedSize)
    }

    func testEmptyArray() throws {
        let original: [Float] = []

        let compressed = original.toCompressedData()
        let decompressed = try [Float].fromCompressedData(compressed)

        XCTAssertEqual(original, decompressed)
    }

    func testLargeArray() throws {
        // 512-dimensional feature vector typical for audio
        let original = (0..<512).map { Float($0) * 0.001 }

        let compressed = original.toCompressedData()
        let decompressed = try [Float].fromCompressedData(compressed)

        XCTAssertEqual(original, decompressed)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter FeatureCompressionTests
```

Expected: FAIL - toCompressedData and fromCompressedData not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/Data/FeatureCompression.swift`:

```swift
import Foundation
import Compression

public enum FeatureCompressionError: Error {
    case decompressionFailed
    case invalidData
}

extension Array where Element == Float {
    /// Compress float array to LZ4-compressed Data
    public func toCompressedData() -> Data {
        guard !isEmpty else { return Data() }

        let byteCount = count * MemoryLayout<Float>.size
        let bytes = withUnsafeBytes { Data($0) }

        // Try to compress with LZ4
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        defer { destinationBuffer.deallocate() }

        let compressedSize = bytes.withUnsafeBytes { sourceBuffer in
            compression_encode_buffer(
                destinationBuffer,
                byteCount,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                byteCount,
                nil,
                COMPRESSION_LZ4
            )
        }

        if compressedSize > 0 && compressedSize < byteCount {
            // Compression succeeded and is smaller
            return Data(bytes: destinationBuffer, count: compressedSize)
        } else {
            // Return uncompressed data with marker
            var result = Data([0xFF])  // Marker for uncompressed
            result.append(bytes)
            return result
        }
    }

    /// Decompress LZ4-compressed Data to float array
    public static func fromCompressedData(_ data: Data) throws -> [Float] {
        guard !data.isEmpty else { return [] }

        // Check for uncompressed marker
        if data.first == 0xFF {
            let bytes = data.dropFirst()
            let count = bytes.count / MemoryLayout<Float>.size
            return bytes.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self).prefix(count))
            }
        }

        // Estimate decompressed size (LZ4 typically 2-4x compression)
        let estimatedSize = data.count * 10
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: estimatedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourceBuffer in
            compression_decode_buffer(
                destinationBuffer,
                estimatedSize,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                COMPRESSION_LZ4
            )
        }

        guard decompressedSize > 0 else {
            throw FeatureCompressionError.decompressionFailed
        }

        let floatCount = decompressedSize / MemoryLayout<Float>.size
        let floatBuffer = UnsafeRawPointer(destinationBuffer).bindMemory(to: Float.self, capacity: floatCount)
        return Array(UnsafeBufferPointer(start: floatBuffer, count: floatCount))
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter FeatureCompressionTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Data/FeatureCompression.swift
git add CrateBotCore/Tests/CrateBotCoreTests/FeatureCompressionTests.swift
git commit -m "feat: add LZ4 compression utilities for feature vectors

- toCompressedData() compresses [Float] to Data
- fromCompressedData() decompresses back to [Float]
- Falls back to uncompressed if compression doesn't help"
```

---

### Task 2.4: Bookmark Manager

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Data/BookmarkManager.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/BookmarkManagerTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/BookmarkManagerTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class BookmarkManagerTests: XCTestCase {
    var manager: BookmarkManager!
    var testDefaults: UserDefaults!

    override func setUp() {
        testDefaults = UserDefaults(suiteName: "BookmarkManagerTests")!
        testDefaults.removePersistentDomain(forName: "BookmarkManagerTests")
        manager = BookmarkManager(userDefaults: testDefaults)
    }

    override func tearDown() {
        manager.stopAllAccess()
        testDefaults.removePersistentDomain(forName: "BookmarkManagerTests")
    }

    func testInitialStateIsEmpty() {
        XCTAssertTrue(manager.musicFolderURLs.isEmpty)
    }

    func testHasAccessReturnsFalseForUnknownURL() {
        let unknownURL = URL(fileURLWithPath: "/some/random/path")
        XCTAssertFalse(manager.hasAccess(to: unknownURL))
    }

    func testRestoreResultForEmptyBookmarks() {
        let results = manager.restoreAllAccess()
        XCTAssertTrue(results.isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter BookmarkManagerTests
```

Expected: FAIL - BookmarkManager not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/Data/BookmarkManager.swift`:

```swift
import Foundation
import os.log

@Observable
public class BookmarkManager {
    private let bookmarksKey = "musicFolderBookmarks"
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.cratebot", category: "BookmarkManager")

    /// All registered music folder URLs with active access
    public private(set) var musicFolderURLs: [URL] = []

    /// Track which URLs have active security scope access
    private var activeAccessURLs: Set<URL> = []

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Persistence

    /// Save bookmark for a folder, adding to existing bookmarks
    public func addFolderAccess(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var bookmarks = loadBookmarkDictionary()
        bookmarks[url.path] = bookmark
        saveBookmarkDictionary(bookmarks)

        if url.startAccessingSecurityScopedResource() {
            activeAccessURLs.insert(url)
            if !musicFolderURLs.contains(url) {
                musicFolderURLs.append(url)
            }
            logger.info("Added folder access: \(url.path)")
        } else {
            logger.warning("Failed to start security scoped access for: \(url.path)")
        }
    }

    /// Remove a folder from bookmarks
    public func removeFolderAccess(_ url: URL) {
        var bookmarks = loadBookmarkDictionary()
        bookmarks.removeValue(forKey: url.path)
        saveBookmarkDictionary(bookmarks)

        if activeAccessURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeAccessURLs.remove(url)
        }
        musicFolderURLs.removeAll { $0 == url }
        logger.info("Removed folder access: \(url.path)")
    }

    // MARK: - Restoration

    public enum BookmarkRestoreResult: Equatable {
        case restored
        case refreshed
        case accessDenied
        case invalid(String)

        public static func == (lhs: BookmarkRestoreResult, rhs: BookmarkRestoreResult) -> Bool {
            switch (lhs, rhs) {
            case (.restored, .restored), (.refreshed, .refreshed), (.accessDenied, .accessDenied):
                return true
            case (.invalid(let l), .invalid(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    /// Restore access to all saved bookmarks on app launch
    @discardableResult
    public func restoreAllAccess() -> [URL: BookmarkRestoreResult] {
        var results: [URL: BookmarkRestoreResult] = [:]
        let bookmarks = loadBookmarkDictionary()

        for (path, bookmarkData) in bookmarks {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    try addFolderAccess(url)
                    results[url] = .refreshed
                    logger.info("Refreshed stale bookmark: \(url.path)")
                } else if url.startAccessingSecurityScopedResource() {
                    activeAccessURLs.insert(url)
                    musicFolderURLs.append(url)
                    results[url] = .restored
                    logger.info("Restored bookmark: \(url.path)")
                } else {
                    results[url] = .accessDenied
                    logger.warning("Access denied for bookmark: \(url.path)")
                }
            } catch {
                let url = URL(fileURLWithPath: path)
                results[url] = .invalid(error.localizedDescription)
                logger.error("Invalid bookmark for path \(path): \(error.localizedDescription)")
            }
        }

        return results
    }

    // MARK: - Access Control

    /// Check if we have access to a specific file URL
    public func hasAccess(to fileURL: URL) -> Bool {
        musicFolderURLs.contains { folder in
            fileURL.path.hasPrefix(folder.path)
        }
    }

    /// Stop all security-scoped access (call on app terminate)
    public func stopAllAccess() {
        for url in activeAccessURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeAccessURLs.removeAll()
        logger.info("Stopped all security-scoped access")
    }

    // MARK: - Private

    private func loadBookmarkDictionary() -> [String: Data] {
        userDefaults.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }

    private func saveBookmarkDictionary(_ bookmarks: [String: Data]) {
        userDefaults.set(bookmarks, forKey: bookmarksKey)
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter BookmarkManagerTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Data/BookmarkManager.swift
git add CrateBotCore/Tests/CrateBotCoreTests/BookmarkManagerTests.swift
git commit -m "feat: add BookmarkManager for security-scoped file access

- Supports multiple music folders
- Persists bookmarks in UserDefaults
- Handles stale bookmark refresh
- Logging for debugging access issues"
```

---

## Phase 3: Audio Layer

### Task 3.1: Audio Analyzer

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Audio/AudioAnalyzer.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/AudioAnalyzerTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/AudioAnalyzerTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import CrateBotCore

final class AudioAnalyzerTests: XCTestCase {
    var analyzer: AudioAnalyzer!

    override func setUp() {
        analyzer = AudioAnalyzer()
    }

    func testTargetSampleRate() {
        XCTAssertEqual(analyzer.targetSampleRate, 22050)
    }

    func testExtractBufferFromNonexistentFile() async {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/file.mp3")

        do {
            _ = try analyzer.extractPCMBuffer(from: fakeURL)
            XCTFail("Should throw for nonexistent file")
        } catch {
            // Expected
        }
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter AudioAnalyzerTests
```

Expected: FAIL - AudioAnalyzer not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/Audio/AudioAnalyzer.swift`:

```swift
import AVFoundation
import os.log

public class AudioAnalyzer: Sendable {
    public let targetSampleRate: Double = 22050
    private let chunkSize: AVAudioFrameCount = 8192
    private let logger = Logger(subsystem: "com.cratebot", category: "AudioAnalyzer")

    public enum AnalyzerError: Error, LocalizedError {
        case fileReadFailed(URL)
        case formatCreationFailed
        case conversionFailed(String)
        case bufferCreationFailed

        public var errorDescription: String? {
            switch self {
            case .fileReadFailed(let url):
                return "Failed to read audio file: \(url.lastPathComponent)"
            case .formatCreationFailed:
                return "Failed to create audio format"
            case .conversionFailed(let reason):
                return "Audio conversion failed: \(reason)"
            case .bufferCreationFailed:
                return "Failed to create audio buffer"
            }
        }
    }

    public init() {}

    /// Extract PCM buffer from audio file, converting to mono 22050Hz
    public func extractPCMBuffer(from url: URL) throws -> AVAudioPCMBuffer {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AnalyzerError.fileReadFailed(url)
        }

        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: 1
        ) else {
            throw AnalyzerError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
            throw AnalyzerError.formatCreationFailed
        }

        let outputFrameCount = AVAudioFrameCount(
            Double(file.length) * targetSampleRate / file.processingFormat.sampleRate
        )

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            throw AnalyzerError.bufferCreationFailed
        }

        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: chunkSize
        ) else {
            throw AnalyzerError.bufferCreationFailed
        }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
            do {
                try file.read(into: inputBuffer, frameCount: min(inNumPackets, self.chunkSize))

                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        if status == .error {
            throw AnalyzerError.conversionFailed(conversionError?.localizedDescription ?? "Unknown error")
        }

        logger.debug("Extracted \(outputBuffer.frameLength) frames from \(url.lastPathComponent)")
        return outputBuffer
    }

    /// Get raw float samples from buffer
    public func getSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter AudioAnalyzerTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Audio/AudioAnalyzer.swift
git add CrateBotCore/Tests/CrateBotCoreTests/AudioAnalyzerTests.swift
git commit -m "feat: add AudioAnalyzer for deterministic audio extraction

- Converts to mono 22050Hz for consistent feature extraction
- Uses AVAudioConverter with streaming input block
- Handles large files via chunked processing"
```

---

### Task 3.2: Audio Player

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Audio/AudioPlayer.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/AudioPlayerTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/AudioPlayerTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class AudioPlayerTests: XCTestCase {
    func testInitialState() {
        let player = AudioPlayer()

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 0)
    }

    func testPlayNonexistentFile() {
        let player = AudioPlayer()
        let fakeURL = URL(fileURLWithPath: "/nonexistent/file.mp3")

        do {
            try player.play(url: fakeURL)
            XCTFail("Should throw for nonexistent file")
        } catch {
            XCTAssertFalse(player.isPlaying)
        }
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter AudioPlayerTests
```

Expected: FAIL - AudioPlayer not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/Audio/AudioPlayer.swift`:

```swift
import AVFoundation
import Observation

@Observable
public class AudioPlayer {
    private var player: AVAudioPlayer?
    private var displayLink: Timer?

    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    public init() {}

    public func play(url: URL) throws {
        stop()

        player = try AVAudioPlayer(contentsOf: url)
        duration = player?.duration ?? 0
        player?.play()
        isPlaying = true
        startTimeUpdates()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        stopTimeUpdates()
    }

    public func resume() {
        player?.play()
        isPlaying = true
        startTimeUpdates()
    }

    public func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTimeUpdates()
    }

    public func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    public func seek(toProgress progress: Double) {
        let time = progress * duration
        seek(to: time)
    }

    // MARK: - Time Updates

    private func startTimeUpdates() {
        stopTimeUpdates()
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }

    private func stopTimeUpdates() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateTime() {
        guard let player = player else { return }
        currentTime = player.currentTime

        if !player.isPlaying && isPlaying {
            // Playback finished
            isPlaying = false
            stopTimeUpdates()
        }
    }

    deinit {
        stop()
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter AudioPlayerTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Audio/AudioPlayer.swift
git add CrateBotCore/Tests/CrateBotCoreTests/AudioPlayerTests.swift
git commit -m "feat: add AudioPlayer for UI playback

- Observable for SwiftUI binding
- Play, pause, resume, stop, seek controls
- Auto-updating current time for progress display"
```

---

## Phase 4: Feature Extraction

### Task 4.1: Feature Extractor Protocol

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Audio/FeatureExtractor.swift`

**Step 1: Create protocol definition**

Create `CrateBotCore/Sources/CrateBotCore/Audio/FeatureExtractor.swift`:

```swift
import AVFoundation

/// Protocol for audio feature extractors
public protocol FeatureExtractor: Sendable {
    /// Unique identifier for this extractor
    var id: String { get }

    /// Version string for cache invalidation
    var version: String { get }

    /// Number of features this extractor produces
    var featureCount: Int { get }

    /// Extract features from an audio buffer
    func extract(from buffer: AVAudioPCMBuffer) async throws -> [Float]
}

/// Errors that can occur during feature extraction
public enum FeatureExtractionError: Error, LocalizedError {
    case invalidBuffer
    case insufficientData(required: Int, got: Int)
    case extractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBuffer:
            return "Invalid audio buffer provided"
        case .insufficientData(let required, let got):
            return "Insufficient audio data: need \(required) samples, got \(got)"
        case .extractionFailed(let reason):
            return "Feature extraction failed: \(reason)"
        }
    }
}
```

**Step 2: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Audio/FeatureExtractor.swift
git commit -m "feat: add FeatureExtractor protocol

- Define interface for audio feature extractors
- Include id, version for cache invalidation
- Async extraction for background processing"
```

---

### Task 4.2: Spectral Feature Extractor

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Audio/SpectralExtractor.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/SpectralExtractorTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/SpectralExtractorTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import CrateBotCore

final class SpectralExtractorTests: XCTestCase {
    var extractor: SpectralExtractor!

    override func setUp() {
        extractor = SpectralExtractor()
    }

    func testExtractorId() {
        XCTAssertEqual(extractor.id, "spectral")
    }

    func testFeatureCountIsPositive() {
        XCTAssertGreaterThan(extractor.featureCount, 0)
    }

    func testExtractFromSineWave() async throws {
        // Create a 1-second sine wave buffer at 22050 Hz
        let sampleRate: Double = 22050
        let duration: Double = 1.0
        let frequency: Float = 440.0  // A4 note

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * duration))
        else {
            XCTFail("Failed to create test buffer")
            return
        }

        // Generate sine wave
        let frameCount = Int(sampleRate * duration)
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channelData = buffer.floatChannelData {
            for i in 0..<frameCount {
                let phase = 2.0 * Float.pi * frequency * Float(i) / Float(sampleRate)
                channelData[0][i] = sin(phase)
            }
        }

        let features = try await extractor.extract(from: buffer)

        XCTAssertEqual(features.count, extractor.featureCount)
        XCTAssertTrue(features.allSatisfy { $0.isFinite })
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter SpectralExtractorTests
```

Expected: FAIL - SpectralExtractor not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/Audio/SpectralExtractor.swift`:

```swift
import AVFoundation
import Accelerate

/// Extracts spectral features using vDSP (MFCCs, spectral centroid, etc.)
public final class SpectralExtractor: FeatureExtractor, @unchecked Sendable {
    public let id = "spectral"
    public let version = "v1"

    // Feature dimensions
    private let numMFCCs = 13
    private let numChroma = 12
    private let numSpectralStats = 7  // centroid, bandwidth, rolloff, flux, flatness, crest, entropy

    public var featureCount: Int {
        numMFCCs + numChroma + numSpectralStats  // 32 features
    }

    // FFT setup
    private let fftSize = 2048
    private let hopSize = 512
    private var fftSetup: vDSP_DFT_Setup?

    public init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    public func extract(from buffer: AVAudioPCMBuffer) async throws -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            throw FeatureExtractionError.invalidBuffer
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength >= fftSize else {
            throw FeatureExtractionError.insufficientData(required: fftSize, got: frameLength)
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Compute spectrogram
        let spectrogram = computeSpectrogram(samples: samples)

        // Extract features from spectrogram
        var features: [Float] = []

        // MFCCs (mean across frames)
        let mfccs = computeMFCCs(spectrogram: spectrogram)
        features.append(contentsOf: mfccs)

        // Chroma features (mean across frames)
        let chroma = computeChroma(spectrogram: spectrogram)
        features.append(contentsOf: chroma)

        // Spectral statistics
        let stats = computeSpectralStats(spectrogram: spectrogram)
        features.append(contentsOf: stats)

        return features
    }

    // MARK: - Private Methods

    private func computeSpectrogram(samples: [Float]) -> [[Float]] {
        var spectrogram: [[Float]] = []
        let numFrames = (samples.count - fftSize) / hopSize + 1

        for frameIdx in 0..<numFrames {
            let startIdx = frameIdx * hopSize
            let frame = Array(samples[startIdx..<(startIdx + fftSize)])
            let spectrum = computeFFT(frame: frame)
            spectrogram.append(spectrum)
        }

        return spectrogram
    }

    private func computeFFT(frame: [Float]) -> [Float] {
        var windowed = frame
        // Apply Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Compute FFT
        var realIn = windowed
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)

        if let setup = fftSetup {
            vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)
        }

        // Compute magnitude spectrum
        var magnitude = [Float](repeating: 0, count: fftSize / 2)
        var complex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
        vDSP_zvabs(&complex, 1, &magnitude, 1, vDSP_Length(fftSize / 2))

        return magnitude
    }

    private func computeMFCCs(spectrogram: [[Float]]) -> [Float] {
        // Simplified MFCC computation (mean magnitude in mel-spaced bands)
        guard !spectrogram.isEmpty else { return [Float](repeating: 0, count: numMFCCs) }

        let binCount = spectrogram[0].count
        var mfccSum = [Float](repeating: 0, count: numMFCCs)

        for spectrum in spectrogram {
            for i in 0..<numMFCCs {
                let startBin = Int(Float(i) / Float(numMFCCs) * Float(binCount))
                let endBin = Int(Float(i + 1) / Float(numMFCCs) * Float(binCount))
                let bandEnergy = spectrum[startBin..<endBin].reduce(0, +) / Float(endBin - startBin)
                mfccSum[i] += log(bandEnergy + 1e-10)
            }
        }

        return mfccSum.map { $0 / Float(spectrogram.count) }
    }

    private func computeChroma(spectrogram: [[Float]]) -> [Float] {
        // Simplified chroma: fold spectrum into 12 pitch classes
        guard !spectrogram.isEmpty else { return [Float](repeating: 0, count: numChroma) }

        var chromaSum = [Float](repeating: 0, count: numChroma)

        for spectrum in spectrogram {
            for (binIdx, magnitude) in spectrum.enumerated() {
                let pitchClass = binIdx % numChroma
                chromaSum[pitchClass] += magnitude
            }
        }

        let total = chromaSum.reduce(0, +) + 1e-10
        return chromaSum.map { $0 / total }
    }

    private func computeSpectralStats(spectrogram: [[Float]]) -> [Float] {
        guard !spectrogram.isEmpty else { return [Float](repeating: 0, count: numSpectralStats) }

        var centroidSum: Float = 0
        var bandwidthSum: Float = 0
        var rolloffSum: Float = 0
        var fluxSum: Float = 0
        var flatnessSum: Float = 0
        var crestSum: Float = 0
        var entropySum: Float = 0

        var prevSpectrum: [Float]?

        for spectrum in spectrogram {
            let total = spectrum.reduce(0, +) + 1e-10

            // Centroid
            var weightedSum: Float = 0
            for (i, mag) in spectrum.enumerated() {
                weightedSum += Float(i) * mag
            }
            centroidSum += weightedSum / total

            // Bandwidth (spread around centroid)
            let centroid = weightedSum / total
            var variance: Float = 0
            for (i, mag) in spectrum.enumerated() {
                variance += mag * pow(Float(i) - centroid, 2)
            }
            bandwidthSum += sqrt(variance / total)

            // Rolloff (frequency below which 85% of energy)
            let threshold = total * 0.85
            var cumSum: Float = 0
            var rolloffBin = 0
            for (i, mag) in spectrum.enumerated() {
                cumSum += mag
                if cumSum >= threshold {
                    rolloffBin = i
                    break
                }
            }
            rolloffSum += Float(rolloffBin)

            // Spectral flux (change from previous frame)
            if let prev = prevSpectrum {
                var flux: Float = 0
                for i in 0..<spectrum.count {
                    flux += pow(spectrum[i] - prev[i], 2)
                }
                fluxSum += sqrt(flux)
            }
            prevSpectrum = spectrum

            // Flatness (geometric mean / arithmetic mean)
            let arithmeticMean = total / Float(spectrum.count)
            var logSum: Float = 0
            for mag in spectrum {
                logSum += log(mag + 1e-10)
            }
            let geometricMean = exp(logSum / Float(spectrum.count))
            flatnessSum += geometricMean / (arithmeticMean + 1e-10)

            // Crest factor (peak / RMS)
            let peak = spectrum.max() ?? 0
            var sumSquares: Float = 0
            vDSP_svesq(spectrum, 1, &sumSquares, vDSP_Length(spectrum.count))
            let rms = sqrt(sumSquares / Float(spectrum.count))
            crestSum += peak / (rms + 1e-10)

            // Entropy
            var entropy: Float = 0
            for mag in spectrum {
                let p = mag / total
                if p > 1e-10 {
                    entropy -= p * log(p)
                }
            }
            entropySum += entropy
        }

        let count = Float(spectrogram.count)
        return [
            centroidSum / count,
            bandwidthSum / count,
            rolloffSum / count,
            fluxSum / count,
            flatnessSum / count,
            crestSum / count,
            entropySum / count
        ]
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter SpectralExtractorTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Audio/SpectralExtractor.swift
git add CrateBotCore/Tests/CrateBotCoreTests/SpectralExtractorTests.swift
git commit -m "feat: add SpectralExtractor for audio feature extraction

- 13 MFCCs (mel-frequency cepstral coefficients)
- 12 chroma features (pitch class distribution)
- 7 spectral statistics (centroid, bandwidth, rolloff, flux, flatness, crest, entropy)
- Uses vDSP for efficient FFT computation"
```

---

## Phase 5: ML Layer

### Task 5.1: Tag Classifier

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/TagClassifier.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/TagClassifierTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/TagClassifierTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class TagClassifierTests: XCTestCase {
    func testTagClassifierErrorDescriptions() {
        let invalidOutput = TagClassifierError.invalidOutput
        XCTAssertNotNil(invalidOutput.errorDescription)

        let dimensionMismatch = TagClassifierError.featureDimensionMismatch(expected: 512, got: 256)
        XCTAssertTrue(dimensionMismatch.errorDescription?.contains("512") ?? false)
    }

    func testMultiLabelPredictorEmptyClassifiers() async throws {
        let predictor = MultiLabelPredictor(classifiers: [])
        let features = [Float](repeating: 0.5, count: 32)

        let tags = try await predictor.predict(features: features)
        XCTAssertEqual(tags, [])
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter TagClassifierTests
```

Expected: FAIL - TagClassifier types not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/ML/TagClassifier.swift`:

```swift
import CoreML
import os.log

public enum TagClassifierError: Error, LocalizedError {
    case invalidOutput
    case featureDimensionMismatch(expected: Int, got: Int)
    case modelLoadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "Model produced invalid output format"
        case .featureDimensionMismatch(let expected, let got):
            return "Feature dimension mismatch: expected \(expected), got \(got)"
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        }
    }
}

/// Wrapper for CoreML binary classifier with proper MLFeatureProvider usage
public class TagClassifier: @unchecked Sendable {
    public let tagName: String
    public let threshold: Float

    private let compiledModel: MLModel
    private let featureInputKey: String
    private let probabilityOutputKey: String
    private let expectedFeatureCount: Int
    private let logger = Logger(subsystem: "com.cratebot", category: "TagClassifier")

    public init(tagName: String, modelURL: URL, threshold: Float) throws {
        self.tagName = tagName
        self.threshold = threshold

        do {
            self.compiledModel = try MLModel(contentsOf: modelURL)
        } catch {
            throw TagClassifierError.modelLoadFailed(error.localizedDescription)
        }

        let description = compiledModel.modelDescription

        guard let inputKey = description.inputDescriptionsByName.keys.first,
              let inputDescription = description.inputDescriptionsByName[inputKey],
              case .multiArray(let constraint) = inputDescription.type else {
            throw TagClassifierError.modelLoadFailed("Model must have multiArray input")
        }

        self.featureInputKey = inputKey
        self.expectedFeatureCount = constraint.shape.first?.intValue ?? 0

        self.probabilityOutputKey = description.outputDescriptionsByName
            .first { $0.value.type == .dictionary }?.key ?? "probability"

        logger.debug("Loaded classifier for '\(tagName)' with threshold \(threshold)")
    }

    public func predict(features: [Float]) throws -> Bool {
        guard features.count == expectedFeatureCount else {
            throw TagClassifierError.featureDimensionMismatch(
                expected: expectedFeatureCount,
                got: features.count
            )
        }

        let multiArray = try MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .float32)
        for (i, value) in features.enumerated() {
            multiArray[i] = NSNumber(value: value)
        }

        let inputProvider = try MLDictionaryFeatureProvider(dictionary: [
            featureInputKey: MLFeatureValue(multiArray: multiArray)
        ])

        let output = try compiledModel.prediction(from: inputProvider)

        guard let probabilityDict = output.featureValue(for: probabilityOutputKey)?.dictionaryValue,
              let positiveProb = probabilityDict["positive"] as? Double else {
            throw TagClassifierError.invalidOutput
        }

        let result = Float(positiveProb) > threshold
        logger.debug("'\(self.tagName)' prediction: \(positiveProb) -> \(result)")
        return result
    }

    public func predictWithConfidence(features: [Float]) throws -> (result: Bool, confidence: Float) {
        guard features.count == expectedFeatureCount else {
            throw TagClassifierError.featureDimensionMismatch(
                expected: expectedFeatureCount,
                got: features.count
            )
        }

        let multiArray = try MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .float32)
        for (i, value) in features.enumerated() {
            multiArray[i] = NSNumber(value: value)
        }

        let inputProvider = try MLDictionaryFeatureProvider(dictionary: [
            featureInputKey: MLFeatureValue(multiArray: multiArray)
        ])

        let output = try compiledModel.prediction(from: inputProvider)

        guard let probabilityDict = output.featureValue(for: probabilityOutputKey)?.dictionaryValue,
              let positiveProb = probabilityDict["positive"] as? Double else {
            throw TagClassifierError.invalidOutput
        }

        let confidence = Float(positiveProb)
        return (confidence > threshold, confidence)
    }
}

/// Predicts multiple tags using binary classifiers
public actor MultiLabelPredictor {
    private let classifiers: [TagClassifier]
    private let logger = Logger(subsystem: "com.cratebot", category: "MultiLabelPredictor")

    public init(classifiers: [TagClassifier]) {
        self.classifiers = classifiers
        logger.info("Initialized with \(classifiers.count) classifiers")
    }

    public func predict(features: [Float]) throws -> [String] {
        try classifiers
            .filter { try $0.predict(features: features) }
            .map { $0.tagName }
    }

    public func predictWithConfidences(features: [Float]) throws -> [(tag: String, confidence: Float)] {
        try classifiers.compactMap { classifier in
            let (result, confidence) = try classifier.predictWithConfidence(features: features)
            return result ? (classifier.tagName, confidence) : nil
        }
    }

    public func predictAll(features: [Float]) throws -> [(tag: String, confidence: Float, predicted: Bool)] {
        try classifiers.map { classifier in
            let (result, confidence) = try classifier.predictWithConfidence(features: features)
            return (classifier.tagName, confidence, result)
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter TagClassifierTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TagClassifier.swift
git add CrateBotCore/Tests/CrateBotCoreTests/TagClassifierTests.swift
git commit -m "feat: add TagClassifier and MultiLabelPredictor for CoreML inference

- Proper MLFeatureProvider usage with MLDictionaryFeatureProvider
- Feature dimension validation
- Confidence scores and threshold-based prediction
- Actor-based MultiLabelPredictor for thread safety"
```

---

### Task 5.2: Training Data Generator

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/BinaryTrainingDataGeneratorTests.swift`

**Step 1: Write the failing test**

Create `CrateBotCore/Tests/CrateBotCoreTests/BinaryTrainingDataGeneratorTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class BinaryTrainingDataGeneratorTests: XCTestCase {
    func testMinimumPositiveExamples() {
        XCTAssertEqual(BinaryTrainingDataGenerator.minPositiveExamples, 50)
    }

    func testReturnsNilForInsufficientData() {
        let generator = BinaryTrainingDataGenerator()

        // Create 10 tracks with "funky" tag (below minimum)
        let tracks = (0..<100).map { i in
            TaggedTrack(id: "\(i)", tags: i < 10 ? ["funky"] : [])
        }

        let result = generator.generateTrainingData(for: "funky", from: tracks)
        XCTAssertNil(result)
    }

    func testGeneratesBalancedData() {
        let generator = BinaryTrainingDataGenerator()

        // Create 60 positive and 200 negative tracks
        let tracks = (0..<260).map { i in
            TaggedTrack(id: "\(i)", tags: i < 60 ? ["funky"] : [])
        }

        let result = generator.generateTrainingData(for: "funky", from: tracks)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.positive.count, 60)
        // Max negative ratio is 3:1, so max 180 negatives
        XCTAssertLessThanOrEqual(result?.negative.count ?? 0, 180)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore
swift test --filter BinaryTrainingDataGeneratorTests
```

Expected: FAIL - Types not defined

**Step 3: Write minimal implementation**

Create `CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift`:

```swift
import Foundation

/// Represents a track with its associated tags
public struct TaggedTrack: Identifiable, Sendable {
    public let id: String
    public let tags: Set<String>
    public let features: [Float]?

    public init(id: String, tags: Set<String>, features: [Float]? = nil) {
        self.id = id
        self.tags = tags
        self.features = features
    }

    public init(id: String, tags: [String], features: [Float]? = nil) {
        self.id = id
        self.tags = Set(tags)
        self.features = features
    }
}

/// Generates balanced training data for binary classifiers
public struct BinaryTrainingDataGenerator: Sendable {
    /// Minimum positive examples required to train a tag classifier
    public static let minPositiveExamples = 50

    /// Maximum negative:positive ratio to prevent class imbalance
    public static let maxNegativeRatio = 3.0

    public init() {}

    /// Generate balanced positive/negative training sets for a specific tag
    public func generateTrainingData(
        for tagName: String,
        from tracks: [TaggedTrack]
    ) -> (positive: [TaggedTrack], negative: [TaggedTrack])? {
        let positive = tracks.filter { $0.tags.contains(tagName) }
        let negative = tracks.filter { !$0.tags.contains(tagName) }

        // Skip tags with insufficient data
        guard positive.count >= Self.minPositiveExamples else {
            return nil
        }

        // Balance negative samples to avoid overwhelming positives
        let maxNegatives = Int(Double(positive.count) * Self.maxNegativeRatio)
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

        return tagCounts.filter { $0.value >= Self.minPositiveExamples }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore
swift test --filter BinaryTrainingDataGeneratorTests
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift
git add CrateBotCore/Tests/CrateBotCoreTests/BinaryTrainingDataGeneratorTests.swift
git commit -m "feat: add BinaryTrainingDataGenerator for balanced training sets

- Minimum 50 positive examples required
- 3:1 max negative:positive ratio
- viableTags() to identify trainable tags"
```

---

## Phase 6: Export Core Library

### Task 6.1: Create Public API Exports

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/CrateBotCore.swift`

**Step 1: Update exports**

Update `CrateBotCore/Sources/CrateBotCore/CrateBotCore.swift`:

```swift
import Foundation

/// CrateBotCore - Shared library for CrateBot applications
public enum CrateBotCore {
    public static let version = "1.0.0"
}

// Re-export all public types
@_exported import struct Foundation.Data
@_exported import struct Foundation.Date
@_exported import struct Foundation.URL
```

**Step 2: Run all tests**

```bash
cd CrateBotCore
swift test
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/CrateBotCore.swift
git commit -m "chore: finalize CrateBotCore Phase 1 exports

- All data layer components ready
- Audio analysis and playback ready
- Feature extraction ready
- ML inference layer ready"
```

---

## Checkpoint: Phase 1-6 Complete

At this point, CrateBotCore contains:

| Module | Components |
|--------|------------|
| Data | CachedFeatures, TagOverride, FeaturePipelineVersion, FeatureCompression, BookmarkManager |
| Audio | AudioAnalyzer, AudioPlayer, FeatureExtractor protocol, SpectralExtractor |
| ML | TagClassifier, MultiLabelPredictor, BinaryTrainingDataGenerator, TaggedTrack |

**Next phases (not yet detailed):**
- Phase 7: Main App Skeleton (CrateBotApp.swift, basic views)
- Phase 8: Model Lab App (experimentation UI)
- Phase 9: Full UI Implementation (all views from design)
- Phase 10: Integrations (Anthropic, WhisperKit)
- Phase 11: Migration (legacy data import)
- Phase 12: Distribution (notarization, Sparkle)

---

## How to Continue

This plan covers the foundational layers. To continue:

1. **Complete Phases 1-6** using this plan
2. **Run verification**: `cd CrateBotCore && swift test`
3. **Use superpowers:writing-plans** to detail Phases 7-12 when ready

Each subsequent phase will build on the foundation established here.
