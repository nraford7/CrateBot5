# CrateBot Native Swift Rewrite - Phases 10-12 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the CrateBot Swift rewrite by adding ID3 tag integration, AI-powered vibe generation, hook detection, legacy data migration, and distribution infrastructure.

**Architecture:** Swift-native ID3 handling via ID3TagEditor SPM package. Vibe generation and hook detection call the existing Python backend via HTTP. Legacy migration imports CrateBot3 data into SwiftData. Distribution uses Xcode code signing, Apple notarization, and Sparkle 2.x for auto-updates.

**Tech Stack:** Swift 5.9+, ID3TagEditor (SPM), URLSession, SwiftData, Sparkle 2.x, Xcode notarization tools

**Worktree:** Continue in `.worktrees/swift-ui-phase`

---

## Phase 10: Integrations

### Task 10.1: ID3 Tag Reading/Writing

**Files:**
- Modify: `CrateBotCore/Package.swift` (add ID3TagEditor dependency)
- Create: `CrateBotCore/Sources/CrateBotCore/Tags/ID3Manager.swift`
- Create: `CrateBotCore/Sources/CrateBotCore/Tags/TagMapping.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Tags/ID3ManagerTests.swift`

**Step 1: Add ID3TagEditor dependency**

Modify `CrateBotCore/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CrateBotCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrateBotCore", targets: ["CrateBotCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/chicio/ID3TagEditor.git", from: "4.6.0")
    ],
    targets: [
        .target(
            name: "CrateBotCore",
            dependencies: ["ID3TagEditor"],
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

**Step 2: Create TagMapping for ID3 frame constants**

Create `CrateBotCore/Sources/CrateBotCore/Tags/TagMapping.swift`:

```swift
import Foundation

/// Maps CrateBot tag categories to ID3v2 frames
public enum TagMapping {
    /// Standard frame mappings matching Python backend
    public static let genre = "TCON"           // Content type (genre)
    public static let timing = "TALB"          // Album (used for timing)
    public static let mood = "TIT1"            // Content group (mood)
    public static let comments = "COMM"        // Comments (descriptive tags)
    public static let title = "TIT2"           // Title
    public static let artist = "TPE1"          // Lead artist
    public static let vibeShort = "TCOM"       // Composer (short vibe tag)
    public static let vibeDescription = "TIT3" // Subtitle (vibe description)
    public static let scene = "MVNM"           // Movement name (scene)
    public static let hook = "TXXX"            // User-defined (hook phrase)

    /// Known genre values (anything else in TCON is treated as timing)
    public static let knownGenres: Set<String> = [
        "House", "Techno", "Jungle", "Rap", "DiscoFunk",
        "PartyBreaks", "Acapella", "Dub/Reggae"
    ]

    /// Determines if a TCON value is a genre or timing
    public static func isGenre(_ value: String) -> Bool {
        knownGenres.contains(value)
    }
}

/// Represents extracted tags from an MP3 file
public struct ExtractedTags: Sendable {
    public var title: String?
    public var artist: String?
    public var genre: String?
    public var timing: String?
    public var mood: String?
    public var comments: [String]
    public var vibeShort: String?
    public var vibeDescription: String?
    public var scene: String?
    public var hook: String?

    public init(
        title: String? = nil,
        artist: String? = nil,
        genre: String? = nil,
        timing: String? = nil,
        mood: String? = nil,
        comments: [String] = [],
        vibeShort: String? = nil,
        vibeDescription: String? = nil,
        scene: String? = nil,
        hook: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.genre = genre
        self.timing = timing
        self.mood = mood
        self.comments = comments
        self.vibeShort = vibeShort
        self.vibeDescription = vibeDescription
        self.scene = scene
        self.hook = hook
    }
}

/// Tags to write to an MP3 file
public struct TagsToWrite: Sendable {
    public var genre: String?
    public var timing: String?
    public var mood: String?
    public var comments: [String]?
    public var vibeShort: String?
    public var vibeDescription: String?
    public var scene: String?
    public var hook: String?
    public var overwrite: Bool

    public init(
        genre: String? = nil,
        timing: String? = nil,
        mood: String? = nil,
        comments: [String]? = nil,
        vibeShort: String? = nil,
        vibeDescription: String? = nil,
        scene: String? = nil,
        hook: String? = nil,
        overwrite: Bool = true
    ) {
        self.genre = genre
        self.timing = timing
        self.mood = mood
        self.comments = comments
        self.vibeShort = vibeShort
        self.vibeDescription = vibeDescription
        self.scene = scene
        self.hook = hook
        self.overwrite = overwrite
    }
}
```

**Step 3: Create ID3Manager**

Create `CrateBotCore/Sources/CrateBotCore/Tags/ID3Manager.swift`:

```swift
import Foundation
import ID3TagEditor
import os.log

/// Manages reading and writing ID3 tags from MP3 files
public actor ID3Manager {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "ID3Manager")
    private let editor = ID3TagEditor()

    public init() {}

    public enum ID3Error: Error, LocalizedError {
        case fileNotFound(URL)
        case readFailed(URL, String)
        case writeFailed(URL, String)
        case invalidFormat(URL)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "File not found: \(url.lastPathComponent)"
            case .readFailed(let url, let reason):
                return "Failed to read tags from \(url.lastPathComponent): \(reason)"
            case .writeFailed(let url, let reason):
                return "Failed to write tags to \(url.lastPathComponent): \(reason)"
            case .invalidFormat(let url):
                return "Invalid audio format: \(url.lastPathComponent)"
            }
        }
    }

    /// Read tags from an MP3 file
    public func readTags(from url: URL) throws -> ExtractedTags {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ID3Error.fileNotFound(url)
        }

        guard url.pathExtension.lowercased() == "mp3" else {
            throw ID3Error.invalidFormat(url)
        }

        do {
            guard let id3Tag = try editor.read(from: url.path) else {
                logger.debug("No ID3 tags found in \(url.lastPathComponent)")
                return ExtractedTags()
            }

            return extractTags(from: id3Tag)
        } catch {
            throw ID3Error.readFailed(url, error.localizedDescription)
        }
    }

    /// Write tags to an MP3 file
    public func writeTags(_ tags: TagsToWrite, to url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ID3Error.fileNotFound(url)
        }

        guard url.pathExtension.lowercased() == "mp3" else {
            throw ID3Error.invalidFormat(url)
        }

        do {
            // Read existing tags first
            var id3Tag = try editor.read(from: url.path) ?? ID32v3TagBuilder().build()

            // Apply new tags
            id3Tag = applyTags(tags, to: id3Tag, overwrite: tags.overwrite)

            // Write back
            try editor.write(tag: id3Tag, to: url.path)
            logger.info("Successfully wrote tags to \(url.lastPathComponent)")
        } catch {
            throw ID3Error.writeFailed(url, error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func extractTags(from id3Tag: ID3Tag) -> ExtractedTags {
        var tags = ExtractedTags()

        // Title
        if case .stringValue(let value) = id3Tag.frames[.title]?.content {
            tags.title = value
        }

        // Artist
        if case .stringValue(let value) = id3Tag.frames[.artist]?.content {
            tags.artist = value
        }

        // Genre (TCON) - may contain genre OR timing
        if case .stringValue(let value) = id3Tag.frames[.genre]?.content {
            if TagMapping.isGenre(value) {
                tags.genre = value
            } else {
                tags.timing = value
                tags.genre = "House" // Default genre when TCON has timing
            }
        }

        // Album (TALB) - used for timing in our system
        if case .stringValue(let value) = id3Tag.frames[.album]?.content {
            // If we already have timing from TCON, album might have genre
            if tags.timing == nil {
                tags.timing = value
            }
        }

        // Content Group (TIT1) - mood
        if case .stringValue(let value) = id3Tag.frames[.contentGrouping]?.content {
            tags.mood = value
        }

        // Comments (COMM) - may have multiple
        if case .stringValue(let value) = id3Tag.frames[.unsyncedLyrics]?.content {
            tags.comments = value.components(separatedBy: "; ").filter { !$0.isEmpty }
        }

        // Composer (TCOM) - short vibe tag
        if case .stringValue(let value) = id3Tag.frames[.composer]?.content {
            tags.vibeShort = value
        }

        // Subtitle (TIT3) - vibe description
        if case .stringValue(let value) = id3Tag.frames[.subtitle]?.content {
            tags.vibeDescription = value
        }

        return tags
    }

    private func applyTags(_ tags: TagsToWrite, to existingTag: ID3Tag, overwrite: Bool) -> ID3Tag {
        var builder = ID32v3TagBuilder()

        // Copy existing frames if not overwriting
        if !overwrite {
            // Preserve existing values
            for (frameId, frame) in existingTag.frames {
                if case .stringValue(let value) = frame.content {
                    switch frameId {
                    case .title:
                        builder = builder.title(frame: ID3FrameWithStringContent(content: value))
                    case .artist:
                        builder = builder.artist(frame: ID3FrameWithStringContent(content: value))
                    case .genre:
                        builder = builder.genre(frame: ID3FrameGenre(genre: nil, description: value))
                    case .album:
                        builder = builder.album(frame: ID3FrameWithStringContent(content: value))
                    default:
                        break
                    }
                }
            }
        }

        // Apply new tags
        if let genre = tags.genre {
            builder = builder.genre(frame: ID3FrameGenre(genre: nil, description: genre))
        }

        if let timing = tags.timing {
            builder = builder.album(frame: ID3FrameWithStringContent(content: timing))
        }

        if let mood = tags.mood {
            builder = builder.contentGrouping(frame: ID3FrameWithStringContent(content: mood))
        }

        if let comments = tags.comments, !comments.isEmpty {
            let commentString = comments.joined(separator: "; ")
            builder = builder.unsyncedLyrics(
                frame: ID3FrameWithLocalizedContent(
                    language: .eng,
                    contentDescription: "",
                    content: commentString
                )
            )
        }

        if let vibeShort = tags.vibeShort {
            builder = builder.composer(frame: ID3FrameWithStringContent(content: vibeShort))
        }

        if let vibeDescription = tags.vibeDescription {
            builder = builder.subtitle(frame: ID3FrameWithStringContent(content: vibeDescription))
        }

        return builder.build()
    }
}
```

**Step 4: Write tests**

Create `CrateBotCore/Tests/CrateBotCoreTests/Tags/ID3ManagerTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class ID3ManagerTests: XCTestCase {
    var manager: ID3Manager!
    var testFileURL: URL!

    override func setUp() async throws {
        manager = ID3Manager()
        // Use a test MP3 file from test resources
        testFileURL = Bundle.module.url(forResource: "test_audio", withExtension: "mp3")
    }

    func testTagMappingKnownGenres() {
        XCTAssertTrue(TagMapping.isGenre("House"))
        XCTAssertTrue(TagMapping.isGenre("Techno"))
        XCTAssertFalse(TagMapping.isGenre("Peak"))
        XCTAssertFalse(TagMapping.isGenre("Warm-up"))
    }

    func testReadTagsFromNonexistentFile() async {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/file.mp3")

        do {
            _ = try await manager.readTags(from: fakeURL)
            XCTFail("Expected error for nonexistent file")
        } catch let error as ID3Manager.ID3Error {
            if case .fileNotFound = error {
                // Expected
            } else {
                XCTFail("Expected fileNotFound error")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testExtractedTagsInitialization() {
        let tags = ExtractedTags(
            title: "Test Track",
            artist: "Test Artist",
            genre: "House",
            timing: "Peak"
        )

        XCTAssertEqual(tags.title, "Test Track")
        XCTAssertEqual(tags.artist, "Test Artist")
        XCTAssertEqual(tags.genre, "House")
        XCTAssertEqual(tags.timing, "Peak")
        XCTAssertNil(tags.mood)
        XCTAssertTrue(tags.comments.isEmpty)
    }

    func testTagsToWriteDefaults() {
        let tags = TagsToWrite(genre: "Techno")

        XCTAssertEqual(tags.genre, "Techno")
        XCTAssertNil(tags.timing)
        XCTAssertTrue(tags.overwrite)
    }
}
```

**Step 5: Run tests**

```bash
cd CrateBotCore && swift test --filter ID3ManagerTests
```

**Step 6: Commit**

```bash
git add CrateBotCore/Package.swift CrateBotCore/Sources/CrateBotCore/Tags/ CrateBotCore/Tests/CrateBotCoreTests/Tags/
git commit -m "feat: add ID3 tag reading and writing via ID3TagEditor

- ID3Manager actor for thread-safe tag operations
- TagMapping with frame constants matching Python backend
- ExtractedTags and TagsToWrite models
- Genre/timing disambiguation from TCON frame"
```

---

### Task 10.2: Vibe Generation (Anthropic API)

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Networking/HTTPClient.swift`
- Create: `CrateBotCore/Sources/CrateBotCore/Networking/BackendAPI.swift`
- Create: `CrateBotCore/Sources/CrateBotCore/Integrations/VibeGenerator.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/VibeGeneratorTests.swift`

**Step 1: Create HTTPClient**

Create `CrateBotCore/Sources/CrateBotCore/Networking/HTTPClient.swift`:

```swift
import Foundation
import os.log

/// Simple HTTP client for backend communication
public actor HTTPClient {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "HTTPClient")
    private let session: URLSession
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8742")!) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    public enum HTTPError: Error, LocalizedError {
        case invalidURL(String)
        case requestFailed(Int, String)
        case decodingFailed(String)
        case networkError(String)
        case serverNotRunning

        public var errorDescription: String? {
            switch self {
            case .invalidURL(let path):
                return "Invalid URL path: \(path)"
            case .requestFailed(let code, let message):
                return "Request failed (\(code)): \(message)"
            case .decodingFailed(let message):
                return "Failed to decode response: \(message)"
            case .networkError(let message):
                return "Network error: \(message)"
            case .serverNotRunning:
                return "Backend server is not running"
            }
        }
    }

    /// Check if backend server is running
    public func healthCheck() async -> Bool {
        do {
            let url = baseURL.appendingPathComponent("/api/v1/health")
            let (_, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            logger.warning("Health check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// POST request with JSON body
    public func post<T: Encodable, R: Decodable>(
        path: String,
        body: T
    ) async throws -> R {
        let url = baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPError.networkError("Invalid response type")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw HTTPError.requestFailed(httpResponse.statusCode, message)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            do {
                return try decoder.decode(R.self, from: data)
            } catch {
                throw HTTPError.decodingFailed(error.localizedDescription)
            }
        } catch let error as HTTPError {
            throw error
        } catch {
            if (error as NSError).code == NSURLErrorCannotConnectToHost {
                throw HTTPError.serverNotRunning
            }
            throw HTTPError.networkError(error.localizedDescription)
        }
    }

    /// GET request
    public func get<R: Decodable>(path: String) async throws -> R {
        let url = baseURL.appendingPathComponent(path)

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPError.networkError("Invalid response type")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw HTTPError.requestFailed(httpResponse.statusCode, message)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(R.self, from: data)
        } catch let error as HTTPError {
            throw error
        } catch {
            if (error as NSError).code == NSURLErrorCannotConnectToHost {
                throw HTTPError.serverNotRunning
            }
            throw HTTPError.networkError(error.localizedDescription)
        }
    }
}
```

**Step 2: Create BackendAPI types**

Create `CrateBotCore/Sources/CrateBotCore/Networking/BackendAPI.swift`:

```swift
import Foundation

/// Backend API request/response types matching Python FastAPI
public enum BackendAPI {

    // MARK: - Vibe Generation

    public struct VibeRequest: Codable, Sendable {
        public let filePath: String
        public let includeHook: Bool
        public let includeScene: Bool

        public init(filePath: String, includeHook: Bool = true, includeScene: Bool = true) {
            self.filePath = filePath
            self.includeHook = includeHook
            self.includeScene = includeScene
        }
    }

    public struct VibeResponse: Codable, Sendable {
        public let vibe: String
        public let description: String?
        public let hook: String?
        public let hookConfidence: Double?
        public let scene: String?
        public let sceneConfidence: Double?
        public let cached: Bool

        public init(
            vibe: String,
            description: String? = nil,
            hook: String? = nil,
            hookConfidence: Double? = nil,
            scene: String? = nil,
            sceneConfidence: Double? = nil,
            cached: Bool = false
        ) {
            self.vibe = vibe
            self.description = description
            self.hook = hook
            self.hookConfidence = hookConfidence
            self.scene = scene
            self.sceneConfidence = sceneConfidence
            self.cached = cached
        }
    }

    // MARK: - Hook Detection

    public struct HookRequest: Codable, Sendable {
        public let filePath: String
        public let artist: String?
        public let title: String?

        public init(filePath: String, artist: String? = nil, title: String? = nil) {
            self.filePath = filePath
            self.artist = artist
            self.title = title
        }
    }

    public struct HookResponse: Codable, Sendable {
        public let hook: String?
        public let confidence: Double
        public let occurrences: Int
        public let transcription: String?
        public let lyricsVerified: Bool?

        public init(
            hook: String?,
            confidence: Double,
            occurrences: Int,
            transcription: String? = nil,
            lyricsVerified: Bool? = nil
        ) {
            self.hook = hook
            self.confidence = confidence
            self.occurrences = occurrences
            self.transcription = transcription
            self.lyricsVerified = lyricsVerified
        }
    }

    // MARK: - Health Check

    public struct HealthResponse: Codable, Sendable {
        public let status: String
        public let version: String
        public let modelLoaded: Bool
        public let anthropicConfigured: Bool
        public let whisperAvailable: Bool
    }

    // MARK: - Settings

    public struct SettingsResponse: Codable, Sendable {
        public let vibeEnabled: Bool
        public let hookEnabled: Bool
        public let whisperModel: String?
        public let defaultModelPath: String?
    }

    public struct APIKeyRequest: Codable, Sendable {
        public let apiKey: String

        public init(apiKey: String) {
            self.apiKey = apiKey
        }
    }
}
```

**Step 3: Create VibeGenerator**

Create `CrateBotCore/Sources/CrateBotCore/Integrations/VibeGenerator.swift`:

```swift
import Foundation
import os.log

/// Generates AI-powered vibe tags via the Python backend
public actor VibeGenerator {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "VibeGenerator")
    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    public enum VibeError: Error, LocalizedError {
        case backendUnavailable
        case generationFailed(String)
        case apiKeyNotConfigured

        public var errorDescription: String? {
            switch self {
            case .backendUnavailable:
                return "Backend server is not available"
            case .generationFailed(let message):
                return "Vibe generation failed: \(message)"
            case .apiKeyNotConfigured:
                return "Anthropic API key is not configured"
            }
        }
    }

    /// Result of vibe generation
    public struct VibeResult: Sendable {
        public let vibe: String              // e.g., "FIERCE AFRO BROKEN GRINDY BASS BUILDER"
        public let description: String?      // e.g., "3am warehouse, dust motes floating like confetti"
        public let hook: String?             // e.g., "let me see you work"
        public let hookConfidence: Double?
        public let scene: String?            // e.g., "Berghain Panorama Bar"
        public let sceneConfidence: Double?
        public let cached: Bool

        public init(
            vibe: String,
            description: String? = nil,
            hook: String? = nil,
            hookConfidence: Double? = nil,
            scene: String? = nil,
            sceneConfidence: Double? = nil,
            cached: Bool = false
        ) {
            self.vibe = vibe
            self.description = description
            self.hook = hook
            self.hookConfidence = hookConfidence
            self.scene = scene
            self.sceneConfidence = sceneConfidence
            self.cached = cached
        }
    }

    /// Check if vibe generation is available
    public func isAvailable() async -> Bool {
        guard await client.healthCheck() else { return false }

        do {
            let settings: BackendAPI.SettingsResponse = try await client.get(path: "/api/v1/settings")
            return settings.vibeEnabled
        } catch {
            logger.warning("Failed to check vibe availability: \(error.localizedDescription)")
            return false
        }
    }

    /// Generate vibe for a file
    public func generateVibe(
        for fileURL: URL,
        includeHook: Bool = true,
        includeScene: Bool = true
    ) async throws -> VibeResult {
        guard await client.healthCheck() else {
            throw VibeError.backendUnavailable
        }

        let request = BackendAPI.VibeRequest(
            filePath: fileURL.path,
            includeHook: includeHook,
            includeScene: includeScene
        )

        do {
            let response: BackendAPI.VibeResponse = try await client.post(
                path: "/api/v1/vibe/file",
                body: request
            )

            logger.info("Generated vibe for \(fileURL.lastPathComponent): \(response.vibe)")

            return VibeResult(
                vibe: response.vibe,
                description: response.description,
                hook: response.hook,
                hookConfidence: response.hookConfidence,
                scene: response.scene,
                sceneConfidence: response.sceneConfidence,
                cached: response.cached
            )
        } catch let error as HTTPClient.HTTPError {
            if case .requestFailed(let code, let message) = error {
                if code == 400 && message.contains("API key") {
                    throw VibeError.apiKeyNotConfigured
                }
            }
            throw VibeError.generationFailed(error.localizedDescription)
        }
    }

    /// Configure API key
    public func setAPIKey(_ key: String) async throws {
        let request = BackendAPI.APIKeyRequest(apiKey: key)
        let _: [String: String] = try await client.post(
            path: "/api/v1/settings/api-key",
            body: request
        )
        logger.info("API key configured successfully")
    }
}
```

**Step 4: Write tests**

Create `CrateBotCore/Tests/CrateBotCoreTests/Integrations/VibeGeneratorTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class VibeGeneratorTests: XCTestCase {

    func testVibeResultInitialization() {
        let result = VibeGenerator.VibeResult(
            vibe: "FIERCE AFRO BROKEN GRINDY BASS BUILDER",
            description: "3am warehouse energy",
            hook: "let me see you work",
            hookConfidence: 0.85,
            scene: "Berlin",
            sceneConfidence: 0.7,
            cached: false
        )

        XCTAssertEqual(result.vibe, "FIERCE AFRO BROKEN GRINDY BASS BUILDER")
        XCTAssertEqual(result.description, "3am warehouse energy")
        XCTAssertEqual(result.hook, "let me see you work")
        XCTAssertEqual(result.hookConfidence, 0.85)
        XCTAssertEqual(result.scene, "Berlin")
        XCTAssertFalse(result.cached)
    }

    func testVibeRequestEncoding() throws {
        let request = BackendAPI.VibeRequest(
            filePath: "/path/to/file.mp3",
            includeHook: true,
            includeScene: false
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["file_path"] as? String, "/path/to/file.mp3")
        XCTAssertEqual(json?["include_hook"] as? Bool, true)
        XCTAssertEqual(json?["include_scene"] as? Bool, false)
    }

    func testVibeResponseDecoding() throws {
        let json = """
        {
            "vibe": "NASTY MIAMI BASS SLAMMER",
            "description": "South Beach vibes",
            "hook": null,
            "hook_confidence": null,
            "scene": "Miami",
            "scene_confidence": 0.6,
            "cached": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.VibeResponse.self, from: json)

        XCTAssertEqual(response.vibe, "NASTY MIAMI BASS SLAMMER")
        XCTAssertEqual(response.description, "South Beach vibes")
        XCTAssertNil(response.hook)
        XCTAssertEqual(response.scene, "Miami")
        XCTAssertTrue(response.cached)
    }
}
```

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Networking/ CrateBotCore/Sources/CrateBotCore/Integrations/VibeGenerator.swift CrateBotCore/Tests/CrateBotCoreTests/Integrations/
git commit -m "feat: add vibe generation via Python backend API

- HTTPClient for backend communication
- BackendAPI types matching FastAPI endpoints
- VibeGenerator actor for AI-powered vibe tags
- Support for vibe, description, hook, and scene"
```

---

### Task 10.3: Hook Detection (WhisperKit)

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Integrations/HookDetector.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/HookDetectorTests.swift`

**Step 1: Create HookDetector**

Create `CrateBotCore/Sources/CrateBotCore/Integrations/HookDetector.swift`:

```swift
import Foundation
import os.log

/// Detects memorable vocal hooks via the Python backend (Whisper-powered)
public actor HookDetector {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "HookDetector")
    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    public enum HookError: Error, LocalizedError {
        case backendUnavailable
        case detectionFailed(String)
        case whisperNotAvailable
        case noVocalsDetected

        public var errorDescription: String? {
            switch self {
            case .backendUnavailable:
                return "Backend server is not available"
            case .detectionFailed(let message):
                return "Hook detection failed: \(message)"
            case .whisperNotAvailable:
                return "Whisper model is not available"
            case .noVocalsDetected:
                return "No vocals detected in track"
            }
        }
    }

    /// Result of hook detection
    public struct HookResult: Sendable {
        public let hook: String?              // The detected hook phrase
        public let confidence: Double         // 0.0 - 1.0
        public let occurrences: Int           // How many times it repeats
        public let transcription: String?     // Full transcribed vocals
        public let lyricsVerified: Bool?      // Verified against lyrics database

        public var hasHook: Bool { hook != nil && confidence > 0.5 }

        public init(
            hook: String?,
            confidence: Double,
            occurrences: Int,
            transcription: String? = nil,
            lyricsVerified: Bool? = nil
        ) {
            self.hook = hook
            self.confidence = confidence
            self.occurrences = occurrences
            self.transcription = transcription
            self.lyricsVerified = lyricsVerified
        }
    }

    /// Check if hook detection is available
    public func isAvailable() async -> Bool {
        guard await client.healthCheck() else { return false }

        do {
            let settings: BackendAPI.SettingsResponse = try await client.get(path: "/api/v1/settings")
            return settings.hookEnabled
        } catch {
            logger.warning("Failed to check hook availability: \(error.localizedDescription)")
            return false
        }
    }

    /// Detect hook in an audio file
    public func detectHook(
        in fileURL: URL,
        artist: String? = nil,
        title: String? = nil
    ) async throws -> HookResult {
        guard await client.healthCheck() else {
            throw HookError.backendUnavailable
        }

        let request = BackendAPI.HookRequest(
            filePath: fileURL.path,
            artist: artist,
            title: title
        )

        do {
            let response: BackendAPI.HookResponse = try await client.post(
                path: "/api/v1/hook/detect",
                body: request
            )

            if let hook = response.hook {
                logger.info("Detected hook in \(fileURL.lastPathComponent): \"\(hook)\" (confidence: \(response.confidence))")
            } else {
                logger.debug("No hook detected in \(fileURL.lastPathComponent)")
            }

            return HookResult(
                hook: response.hook,
                confidence: response.confidence,
                occurrences: response.occurrences,
                transcription: response.transcription,
                lyricsVerified: response.lyricsVerified
            )
        } catch let error as HTTPClient.HTTPError {
            if case .requestFailed(let code, let message) = error {
                if code == 503 && message.contains("Whisper") {
                    throw HookError.whisperNotAvailable
                }
                if message.contains("no vocals") {
                    throw HookError.noVocalsDetected
                }
            }
            throw HookError.detectionFailed(error.localizedDescription)
        }
    }
}
```

**Step 2: Write tests**

Create `CrateBotCore/Tests/CrateBotCoreTests/Integrations/HookDetectorTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class HookDetectorTests: XCTestCase {

    func testHookResultInitialization() {
        let result = HookDetector.HookResult(
            hook: "let me see you work",
            confidence: 0.85,
            occurrences: 4,
            transcription: "let me see you work let me see you work",
            lyricsVerified: true
        )

        XCTAssertEqual(result.hook, "let me see you work")
        XCTAssertEqual(result.confidence, 0.85)
        XCTAssertEqual(result.occurrences, 4)
        XCTAssertTrue(result.hasHook)
        XCTAssertEqual(result.lyricsVerified, true)
    }

    func testHookResultNoHook() {
        let result = HookDetector.HookResult(
            hook: nil,
            confidence: 0.0,
            occurrences: 0
        )

        XCTAssertNil(result.hook)
        XCTAssertFalse(result.hasHook)
    }

    func testHookResultLowConfidence() {
        let result = HookDetector.HookResult(
            hook: "maybe this",
            confidence: 0.3,
            occurrences: 2
        )

        XCTAssertEqual(result.hook, "maybe this")
        XCTAssertFalse(result.hasHook) // Below 0.5 threshold
    }

    func testHookRequestEncoding() throws {
        let request = BackendAPI.HookRequest(
            filePath: "/path/to/file.mp3",
            artist: "Test Artist",
            title: "Test Track"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["file_path"] as? String, "/path/to/file.mp3")
        XCTAssertEqual(json?["artist"] as? String, "Test Artist")
        XCTAssertEqual(json?["title"] as? String, "Test Track")
    }

    func testHookResponseDecoding() throws {
        let json = """
        {
            "hook": "work it out",
            "confidence": 0.75,
            "occurrences": 3,
            "transcription": "work it out work it out yeah work it out",
            "lyrics_verified": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(BackendAPI.HookResponse.self, from: json)

        XCTAssertEqual(response.hook, "work it out")
        XCTAssertEqual(response.confidence, 0.75)
        XCTAssertEqual(response.occurrences, 3)
        XCTAssertEqual(response.lyricsVerified, true)
    }
}
```

**Step 3: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Integrations/HookDetector.swift CrateBotCore/Tests/CrateBotCoreTests/Integrations/
git commit -m "feat: add hook detection via Python backend Whisper

- HookDetector actor for vocal phrase detection
- Confidence scoring and lyrics verification
- Integration with backend /api/v1/hook/detect endpoint"
```

---

## Phase 11: Migration

### Task 11.1: Legacy Data Import

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Data/LegacyImporter.swift`
- Create: `CrateBotCore/Sources/CrateBotCore/Data/LegacyModels.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Data/LegacyImporterTests.swift`

**Step 1: Create LegacyModels**

Create `CrateBotCore/Sources/CrateBotCore/Data/LegacyModels.swift`:

```swift
import Foundation

/// Legacy CrateBot3 data formats for migration
public enum LegacyModels {

    /// Legacy config format (~/.cratebot/config.json)
    public struct LegacyConfig: Codable {
        public let anthropicApiKey: String?
        public let defaultModel: String?
        public let whisperModel: String?
        public let enablePanns: Bool?
        public let enableEssentia: Bool?
        public let lastUsedFolder: String?
        public let recentFolders: [String]?

        enum CodingKeys: String, CodingKey {
            case anthropicApiKey = "anthropic_api_key"
            case defaultModel = "default_model"
            case whisperModel = "whisper_model"
            case enablePanns = "enable_panns"
            case enableEssentia = "enable_essentia"
            case lastUsedFolder = "last_used_folder"
            case recentFolders = "recent_folders"
        }
    }

    /// Legacy refinement session entry
    public struct LegacyRefinementEntry: Codable {
        public let filePath: String
        public let originalTags: [String: String]
        public let correctedTags: [String: String]
        public let timestamp: String

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case originalTags = "original_tags"
            case correctedTags = "corrected_tags"
            case timestamp
        }
    }

    /// Legacy training checkpoint
    public struct LegacyCheckpoint: Codable {
        public let taskId: String
        public let phase: String
        public let progress: Double
        public let processedFiles: [String]
        public let selectedTags: [String: [String]]
        public let timestamp: String

        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case phase
            case progress
            case processedFiles = "processed_files"
            case selectedTags = "selected_tags"
            case timestamp
        }
    }

    /// Detected legacy data summary
    public struct DetectedLegacyData: Sendable {
        public let hasConfig: Bool
        public let hasModels: Bool
        public let modelCount: Int
        public let hasRefinementSession: Bool
        public let refinementEntryCount: Int
        public let hasCheckpoints: Bool
        public let checkpointCount: Int
        public let hasCache: Bool
        public let cacheFileCount: Int

        public var isEmpty: Bool {
            !hasConfig && !hasModels && !hasRefinementSession && !hasCheckpoints && !hasCache
        }
    }
}
```

**Step 2: Create LegacyImporter**

Create `CrateBotCore/Sources/CrateBotCore/Data/LegacyImporter.swift`:

```swift
import Foundation
import SwiftData
import os.log

/// Imports legacy CrateBot3 data into SwiftData
public actor LegacyImporter {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "LegacyImporter")
    private let legacyBasePath: URL
    private let fileManager = FileManager.default

    public init(legacyBasePath: URL? = nil) {
        self.legacyBasePath = legacyBasePath ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cratebot")
    }

    public enum ImportError: Error, LocalizedError {
        case noLegacyData
        case backupFailed(String)
        case migrationFailed(String)
        case rollbackFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noLegacyData:
                return "No legacy CrateBot3 data found"
            case .backupFailed(let reason):
                return "Backup failed: \(reason)"
            case .migrationFailed(let reason):
                return "Migration failed: \(reason)"
            case .rollbackFailed(let reason):
                return "Rollback failed: \(reason)"
            }
        }
    }

    /// Detect what legacy data exists
    public func detectLegacyData() -> LegacyModels.DetectedLegacyData {
        let configPath = legacyBasePath.appendingPathComponent("config.json")
        let modelsPath = legacyBasePath.appendingPathComponent("models")
        let refinementPath = legacyBasePath.appendingPathComponent("data/refinement_session.json")
        let checkpointsPath = legacyBasePath.appendingPathComponent("checkpoints")
        let cachePath = legacyBasePath.appendingPathComponent("cache")

        let hasConfig = fileManager.fileExists(atPath: configPath.path)

        var modelCount = 0
        if let files = try? fileManager.contentsOfDirectory(atPath: modelsPath.path) {
            modelCount = files.filter { $0.hasSuffix(".pkl") }.count
        }

        var refinementEntryCount = 0
        if let data = try? Data(contentsOf: refinementPath),
           let entries = try? JSONDecoder().decode([LegacyModels.LegacyRefinementEntry].self, from: data) {
            refinementEntryCount = entries.count
        }

        var checkpointCount = 0
        if let files = try? fileManager.contentsOfDirectory(atPath: checkpointsPath.path) {
            checkpointCount = files.filter { $0.hasSuffix(".json") }.count
        }

        var cacheFileCount = 0
        if let files = try? fileManager.contentsOfDirectory(atPath: cachePath.path) {
            cacheFileCount = files.count
        }

        return LegacyModels.DetectedLegacyData(
            hasConfig: hasConfig,
            hasModels: modelCount > 0,
            modelCount: modelCount,
            hasRefinementSession: refinementEntryCount > 0,
            refinementEntryCount: refinementEntryCount,
            hasCheckpoints: checkpointCount > 0,
            checkpointCount: checkpointCount,
            hasCache: cacheFileCount > 0,
            cacheFileCount: cacheFileCount
        )
    }

    /// Create timestamped backup before migration
    public func createBackup() throws -> URL {
        guard fileManager.fileExists(atPath: legacyBasePath.path) else {
            throw ImportError.noLegacyData
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "cratebot_backup_\(timestamp)"
        let backupPath = legacyBasePath
            .deletingLastPathComponent()
            .appendingPathComponent(backupName)

        do {
            try fileManager.copyItem(at: legacyBasePath, to: backupPath)
            logger.info("Created backup at \(backupPath.path)")
            return backupPath
        } catch {
            throw ImportError.backupFailed(error.localizedDescription)
        }
    }

    /// Import legacy config to UserDefaults
    public func importConfig() throws -> LegacyModels.LegacyConfig? {
        let configPath = legacyBasePath.appendingPathComponent("config.json")

        guard fileManager.fileExists(atPath: configPath.path) else {
            return nil
        }

        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(LegacyModels.LegacyConfig.self, from: data)

        // Migrate to UserDefaults
        if let apiKey = config.anthropicApiKey {
            UserDefaults.standard.set(apiKey, forKey: "anthropicAPIKey")
        }
        if let whisperModel = config.whisperModel {
            UserDefaults.standard.set(whisperModel, forKey: "whisperModelSize")
        }

        logger.info("Imported legacy config")
        return config
    }

    /// Import refinement corrections into SwiftData
    public func importRefinements(into context: ModelContext) throws -> Int {
        let refinementPath = legacyBasePath.appendingPathComponent("data/refinement_session.json")

        guard fileManager.fileExists(atPath: refinementPath.path) else {
            return 0
        }

        let data = try Data(contentsOf: refinementPath)
        let entries = try JSONDecoder().decode([LegacyModels.LegacyRefinementEntry].self, from: data)

        var importedCount = 0

        for entry in entries {
            // Generate audio hash from file path
            let fileURL = URL(fileURLWithPath: entry.filePath)
            guard let audioHash = try? computeAudioHash(for: fileURL) else {
                logger.warning("Could not compute hash for \(entry.filePath)")
                continue
            }

            // Create TagOverride from corrected tags
            let override = TagOverride(audioHash: audioHash)

            if let genre = entry.correctedTags["genre"] {
                override.genre = genre
            }
            if let timing = entry.correctedTags["timing"] {
                override.timing = timing
            }
            if let mood = entry.correctedTags["mood"] {
                override.mood = mood.components(separatedBy: ", ")
            }
            if let descriptive = entry.correctedTags["descriptive"] {
                override.descriptive = descriptive.components(separatedBy: ", ")
            }

            context.insert(override)
            importedCount += 1
        }

        try context.save()
        logger.info("Imported \(importedCount) refinement entries")
        return importedCount
    }

    /// List available backups
    public func listBackups() -> [URL] {
        let parentDir = legacyBasePath.deletingLastPathComponent()

        guard let contents = try? fileManager.contentsOfDirectory(
            at: parentDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents
            .filter { $0.lastPathComponent.hasPrefix("cratebot_backup_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Restore from backup
    public func restoreBackup(from backupURL: URL) throws {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw ImportError.rollbackFailed("Backup not found")
        }

        do {
            // Remove current data
            if fileManager.fileExists(atPath: legacyBasePath.path) {
                try fileManager.removeItem(at: legacyBasePath)
            }

            // Restore from backup
            try fileManager.copyItem(at: backupURL, to: legacyBasePath)
            logger.info("Restored from backup \(backupURL.lastPathComponent)")
        } catch {
            throw ImportError.rollbackFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func computeAudioHash(for url: URL) throws -> String {
        // Reuse existing hash computation from AudioAnalyzer
        let data = try Data(contentsOf: url)
        return data.sha256Hash()
    }
}

// Extension for hashing
extension Data {
    func sha256Hash() -> String {
        import CryptoKit
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

**Step 3: Write tests**

Create `CrateBotCore/Tests/CrateBotCoreTests/Data/LegacyImporterTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class LegacyImporterTests: XCTestCase {

    func testDetectedLegacyDataEmpty() {
        let detected = LegacyModels.DetectedLegacyData(
            hasConfig: false,
            hasModels: false,
            modelCount: 0,
            hasRefinementSession: false,
            refinementEntryCount: 0,
            hasCheckpoints: false,
            checkpointCount: 0,
            hasCache: false,
            cacheFileCount: 0
        )

        XCTAssertTrue(detected.isEmpty)
    }

    func testDetectedLegacyDataNotEmpty() {
        let detected = LegacyModels.DetectedLegacyData(
            hasConfig: true,
            hasModels: false,
            modelCount: 0,
            hasRefinementSession: false,
            refinementEntryCount: 0,
            hasCheckpoints: false,
            checkpointCount: 0,
            hasCache: false,
            cacheFileCount: 0
        )

        XCTAssertFalse(detected.isEmpty)
    }

    func testLegacyConfigDecoding() throws {
        let json = """
        {
            "anthropic_api_key": "sk-test-123",
            "default_model": "house_classifier",
            "whisper_model": "medium",
            "enable_panns": true,
            "enable_essentia": false,
            "last_used_folder": "/Users/test/Music",
            "recent_folders": ["/Users/test/Music", "/Users/test/Downloads"]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(LegacyModels.LegacyConfig.self, from: json)

        XCTAssertEqual(config.anthropicApiKey, "sk-test-123")
        XCTAssertEqual(config.defaultModel, "house_classifier")
        XCTAssertEqual(config.whisperModel, "medium")
        XCTAssertEqual(config.enablePanns, true)
        XCTAssertEqual(config.enableEssentia, false)
        XCTAssertEqual(config.lastUsedFolder, "/Users/test/Music")
        XCTAssertEqual(config.recentFolders?.count, 2)
    }

    func testLegacyRefinementEntryDecoding() throws {
        let json = """
        {
            "file_path": "/path/to/track.mp3",
            "original_tags": {"genre": "House", "timing": "Peak"},
            "corrected_tags": {"genre": "Techno", "timing": "Build"},
            "timestamp": "2024-01-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(LegacyModels.LegacyRefinementEntry.self, from: json)

        XCTAssertEqual(entry.filePath, "/path/to/track.mp3")
        XCTAssertEqual(entry.originalTags["genre"], "House")
        XCTAssertEqual(entry.correctedTags["genre"], "Techno")
    }
}
```

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Data/Legacy*.swift CrateBotCore/Tests/CrateBotCoreTests/Data/
git commit -m "feat: add legacy CrateBot3 data importer

- LegacyModels for config, refinements, checkpoints
- LegacyImporter with backup/restore support
- Detection and import of legacy refinement corrections"
```

---

### Task 11.2: CoreML Model Conversion

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/ModelManager.swift`
- Create: `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelManagerTests.swift`

**Step 1: Create ModelMetadata**

Create `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift`:

```swift
import Foundation

/// Metadata for a trained CoreML model
public struct ModelMetadata: Codable, Sendable {
    public let name: String
    public let version: String
    public let pipelineVersion: String       // Feature pipeline version for compatibility
    public let trainedAt: Date
    public let trainingFileCount: Int
    public let categories: [String]          // Genre, Timing, Mood, Descriptive
    public let tags: [String: [String]]      // Tags per category
    public let accuracy: Double?             // Validation accuracy if available

    public init(
        name: String,
        version: String,
        pipelineVersion: String,
        trainedAt: Date,
        trainingFileCount: Int,
        categories: [String],
        tags: [String: [String]],
        accuracy: Double? = nil
    ) {
        self.name = name
        self.version = version
        self.pipelineVersion = pipelineVersion
        self.trainedAt = trainedAt
        self.trainingFileCount = trainingFileCount
        self.categories = categories
        self.tags = tags
        self.accuracy = accuracy
    }

    /// Load metadata from JSON sidecar file
    public static func load(from url: URL) throws -> ModelMetadata {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ModelMetadata.self, from: data)
    }

    /// Save metadata to JSON sidecar file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

/// Available model info
public struct AvailableModel: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let url: URL
    public let metadata: ModelMetadata?
    public let isDefault: Bool

    public init(name: String, url: URL, metadata: ModelMetadata?, isDefault: Bool = false) {
        self.name = name
        self.url = url
        self.metadata = metadata
        self.isDefault = isDefault
    }
}
```

**Step 2: Create ModelManager**

Create `CrateBotCore/Sources/CrateBotCore/ML/ModelManager.swift`:

```swift
import Foundation
import CoreML
import os.log

/// Manages CoreML model discovery, loading, and validation
public actor ModelManager {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "ModelManager")
    private let fileManager = FileManager.default

    /// Directories to search for models
    private let modelDirectories: [URL]

    /// Currently loaded model
    private var loadedModel: MultiLabelPredictor?
    private var loadedModelName: String?

    public init() {
        // Default model directories
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("CrateBot/Models")

        // Also check bundle for shipped models
        let bundleModels = Bundle.main.resourceURL?.appendingPathComponent("Models")

        self.modelDirectories = [modelsDir, bundleModels].compactMap { $0 }
    }

    public enum ModelError: Error, LocalizedError {
        case modelNotFound(String)
        case loadFailed(String)
        case incompatiblePipelineVersion(expected: String, found: String)
        case noModelsAvailable

        public var errorDescription: String? {
            switch self {
            case .modelNotFound(let name):
                return "Model not found: \(name)"
            case .loadFailed(let reason):
                return "Failed to load model: \(reason)"
            case .incompatiblePipelineVersion(let expected, let found):
                return "Model pipeline version mismatch: expected \(expected), found \(found)"
            case .noModelsAvailable:
                return "No models available"
            }
        }
    }

    /// List available models
    public func listModels() -> [AvailableModel] {
        var models: [AvailableModel] = []
        let defaultModelName = UserDefaults.standard.string(forKey: "defaultModelName")

        for directory in modelDirectories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }

            for url in contents where url.pathExtension == "mlmodelc" {
                let name = url.deletingPathExtension().lastPathComponent
                let metadataURL = url.deletingPathExtension().appendingPathExtension("json")
                let metadata = try? ModelMetadata.load(from: metadataURL)

                models.append(AvailableModel(
                    name: name,
                    url: url,
                    metadata: metadata,
                    isDefault: name == defaultModelName
                ))
            }
        }

        return models.sorted { $0.name < $1.name }
    }

    /// Load a model by name
    public func loadModel(named name: String) throws -> MultiLabelPredictor {
        // Check if already loaded
        if let loaded = loadedModel, loadedModelName == name {
            return loaded
        }

        // Find the model
        guard let model = listModels().first(where: { $0.name == name }) else {
            throw ModelError.modelNotFound(name)
        }

        // Validate pipeline version if metadata exists
        if let metadata = model.metadata {
            let currentPipelineVersion = FeaturePipelineVersion.current.versionHash
            if metadata.pipelineVersion != currentPipelineVersion {
                logger.warning("Pipeline version mismatch for \(name)")
                // Allow loading but warn
            }
        }

        // Load the model
        do {
            let mlModel = try MLModel(contentsOf: model.url)
            let classifier = try TagClassifier(model: mlModel)
            let predictor = MultiLabelPredictor(classifiers: [classifier])

            loadedModel = predictor
            loadedModelName = name

            logger.info("Loaded model: \(name)")
            return predictor
        } catch {
            throw ModelError.loadFailed(error.localizedDescription)
        }
    }

    /// Load the default model
    public func loadDefaultModel() throws -> MultiLabelPredictor {
        let models = listModels()

        // Try default first
        if let defaultModel = models.first(where: { $0.isDefault }) {
            return try loadModel(named: defaultModel.name)
        }

        // Fall back to first available
        guard let firstModel = models.first else {
            throw ModelError.noModelsAvailable
        }

        return try loadModel(named: firstModel.name)
    }

    /// Set default model
    public func setDefaultModel(name: String) {
        UserDefaults.standard.set(name, forKey: "defaultModelName")
        logger.info("Set default model to: \(name)")
    }

    /// Get the models directory (creating if needed)
    public func modelsDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("CrateBot/Models")

        if !fileManager.fileExists(atPath: modelsDir.path) {
            try fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        return modelsDir
    }

    /// Copy a model to the models directory
    public func installModel(from sourceURL: URL, metadata: ModelMetadata) throws {
        let modelsDir = try modelsDirectory()
        let destURL = modelsDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Copy model
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)

        // Save metadata
        let metadataURL = destURL.deletingPathExtension().appendingPathExtension("json")
        try metadata.save(to: metadataURL)

        logger.info("Installed model: \(metadata.name)")
    }
}
```

**Step 3: Write tests**

Create `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelManagerTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class ModelManagerTests: XCTestCase {

    func testModelMetadataEncoding() throws {
        let metadata = ModelMetadata(
            name: "test_model",
            version: "1.0.0",
            pipelineVersion: "abc123",
            trainedAt: Date(),
            trainingFileCount: 500,
            categories: ["Genre", "Mood"],
            tags: ["Genre": ["House", "Techno"], "Mood": ["Energetic", "Chill"]],
            accuracy: 0.92
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ModelMetadata.self, from: data)

        XCTAssertEqual(decoded.name, "test_model")
        XCTAssertEqual(decoded.version, "1.0.0")
        XCTAssertEqual(decoded.trainingFileCount, 500)
        XCTAssertEqual(decoded.categories.count, 2)
        XCTAssertEqual(decoded.tags["Genre"]?.count, 2)
        XCTAssertEqual(decoded.accuracy, 0.92)
    }

    func testAvailableModelIdentifiable() {
        let model = AvailableModel(
            name: "house_classifier",
            url: URL(fileURLWithPath: "/path/to/model.mlmodelc"),
            metadata: nil,
            isDefault: true
        )

        XCTAssertEqual(model.id, "house_classifier")
        XCTAssertTrue(model.isDefault)
    }

    func testModelManagerListModelsEmpty() async {
        let manager = ModelManager()
        let models = await manager.listModels()
        // May have bundled models, just check it doesn't crash
        XCTAssertNotNil(models)
    }
}
```

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/Model*.swift CrateBotCore/Tests/CrateBotCoreTests/ML/
git commit -m "feat: add CoreML model manager with metadata

- ModelMetadata for version tracking and compatibility
- ModelManager for discovery, loading, and installation
- Pipeline version validation for cache coherence"
```

---

## Phase 12: Distribution

### Task 12.1: App Notarization Setup

**Files:**
- Create: `scripts/notarize.sh`
- Create: `docs/DISTRIBUTION.md`

**Step 1: Create notarization script**

Create `scripts/notarize.sh`:

```bash
#!/bin/bash
set -e

# CrateBot Notarization Script
# Usage: ./scripts/notarize.sh <path-to-app>
#
# Required environment variables:
# - APPLE_ID: Your Apple ID email
# - APPLE_TEAM_ID: Your team ID (10-character string)
# - APPLE_APP_PASSWORD: App-specific password from appleid.apple.com

APP_PATH="${1:?Usage: $0 <path-to-app>}"
APP_NAME=$(basename "$APP_PATH" .app)
BUNDLE_ID="com.cratebot.app"

# Verify environment
if [[ -z "$APPLE_ID" ]] || [[ -z "$APPLE_TEAM_ID" ]] || [[ -z "$APPLE_APP_PASSWORD" ]]; then
    echo "Error: Missing required environment variables"
    echo "  APPLE_ID: Apple ID email"
    echo "  APPLE_TEAM_ID: Team ID"
    echo "  APPLE_APP_PASSWORD: App-specific password"
    exit 1
fi

echo "=== CrateBot Notarization ==="
echo "App: $APP_PATH"
echo "Bundle ID: $BUNDLE_ID"

# Step 1: Create ZIP for notarization
echo ""
echo "Step 1: Creating ZIP archive..."
ZIP_PATH="/tmp/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Created: $ZIP_PATH"

# Step 2: Submit for notarization
echo ""
echo "Step 2: Submitting for notarization..."
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait 2>&1)

echo "$SUBMIT_OUTPUT"

# Check if successful
if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo ""
    echo "Step 3: Stapling ticket to app..."
    xcrun stapler staple "$APP_PATH"
    echo ""
    echo "=== Notarization Complete ==="
    echo "The app is now notarized and ready for distribution."
else
    echo ""
    echo "=== Notarization Failed ==="

    # Extract submission ID for log retrieval
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -o 'id: [a-f0-9-]*' | head -1 | cut -d' ' -f2)

    if [[ -n "$SUBMISSION_ID" ]]; then
        echo "Fetching notarization log..."
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD"
    fi

    exit 1
fi

# Cleanup
rm -f "$ZIP_PATH"
```

**Step 2: Create distribution documentation**

Create `docs/DISTRIBUTION.md`:

```markdown
# CrateBot Distribution Guide

## Prerequisites

1. **Apple Developer Account** with Developer ID certificate
2. **Xcode 15+** installed
3. **App-specific password** from [appleid.apple.com](https://appleid.apple.com)

## Build Process

### 1. Build the App

```bash
# Build release configuration
xcodebuild -scheme CrateBot -configuration Release archive \
    -archivePath build/CrateBot.xcarchive

# Export for distribution
xcodebuild -exportArchive \
    -archivePath build/CrateBot.xcarchive \
    -exportPath build/release \
    -exportOptionsPlist ExportOptions.plist
```

### 2. Code Sign

The app should be signed during the build process with your Developer ID certificate.

Verify signing:
```bash
codesign -dv --verbose=4 build/release/CrateBot.app
```

### 3. Notarize

Set environment variables:
```bash
export APPLE_ID="your@email.com"
export APPLE_TEAM_ID="ABCD123456"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Run notarization:
```bash
./scripts/notarize.sh build/release/CrateBot.app
```

### 4. Create DMG

```bash
./scripts/create-dmg.sh build/release/CrateBot.app
```

## Sparkle Auto-Updates

The app uses Sparkle 2.x for auto-updates. See Task 12.2 for setup.

### Appcast

Updates are published via an appcast XML file hosted at:
```
https://cratebot.app/appcast.xml
```

### Update Signing

Updates are signed with EdDSA. The private key should be stored securely:
```bash
# Generate signing key (one-time)
./bin/generate_keys

# Sign update
./bin/sign_update CrateBot-1.0.1.zip
```

## Troubleshooting

### "App is damaged" error

The app may not be properly stapled. Run:
```bash
xcrun stapler staple CrateBot.app
```

### Gatekeeper rejection

Check notarization status:
```bash
spctl -a -vv CrateBot.app
```

### Code signing issues

Verify entitlements:
```bash
codesign -d --entitlements - CrateBot.app
```
```

**Step 3: Make script executable and commit**

```bash
chmod +x scripts/notarize.sh
git add scripts/notarize.sh docs/DISTRIBUTION.md
git commit -m "feat: add notarization script and distribution docs

- notarize.sh for Apple notarization workflow
- DISTRIBUTION.md with build and release guide"
```

---

### Task 12.2: Sparkle Update Integration

**Files:**
- Modify: `CrateBotCore/Package.swift` (add Sparkle)
- Create: `CrateBot/App/UpdateManager.swift`
- Modify: `CrateBot/App/CrateBotApp.swift` (integrate Sparkle)

**Step 1: Add Sparkle dependency**

Modify `CrateBotCore/Package.swift` to add Sparkle. Note: Sparkle is added to the main app, not CrateBotCore.

For the CrateBot app, create/update the app's Package.swift or Xcode project to include:

```swift
// In CrateBot Xcode project, add SPM dependency:
// https://github.com/sparkle-project/Sparkle.git
// Version: 2.6.0 or later
```

**Step 2: Create UpdateManager**

Create `CrateBot/App/UpdateManager.swift`:

```swift
import Foundation
import Sparkle
import os.log

/// Manages app updates via Sparkle
@Observable
public final class UpdateManager: NSObject {
    private let logger = Logger(subsystem: "com.cratebot.app", category: "UpdateManager")

    /// The Sparkle updater controller
    private var updaterController: SPUStandardUpdaterController!

    /// Whether an update is available
    public private(set) var updateAvailable = false

    /// The available update version (if any)
    public private(set) var availableVersion: String?

    /// Whether currently checking for updates
    public private(set) var isChecking = false

    /// Whether currently downloading/installing
    public private(set) var isUpdating = false

    /// Last check date
    public private(set) var lastCheckDate: Date?

    /// Update check interval (default: 1 hour)
    public var checkInterval: TimeInterval {
        get { updaterController.updater.updateCheckInterval }
        set { updaterController.updater.updateCheckInterval = newValue }
    }

    /// Whether automatic checks are enabled
    public var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    public override init() {
        super.init()

        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Set appcast URL
        if let appcastURL = URL(string: "https://cratebot.app/appcast.xml") {
            updaterController.updater.setFeedURL(appcastURL)
        }

        logger.info("UpdateManager initialized")
    }

    /// Check for updates manually
    public func checkForUpdates() {
        logger.info("Checking for updates...")
        updaterController.checkForUpdates(nil)
    }

    /// Check for updates silently (no UI if no update)
    public func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateManager: SPUUpdaterDelegate {

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        logger.info("Update available: \(item.displayVersionString)")
        updateAvailable = true
        availableVersion = item.displayVersionString
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        logger.debug("No update available")
        updateAvailable = false
        availableVersion = nil
    }

    public func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        isUpdating = true
    }

    public func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        logger.info("Downloaded update: \(item.displayVersionString)")
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        logger.error("Update aborted: \(error.localizedDescription)")
        isUpdating = false
    }

    public func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isChecking = false
        isUpdating = false
        lastCheckDate = Date()

        if let error = error {
            logger.warning("Update cycle finished with error: \(error.localizedDescription)")
        }
    }
}
```

**Step 3: Integrate into CrateBotApp**

Modify `CrateBot/App/CrateBotApp.swift`:

```swift
import SwiftUI
import SwiftData
import CrateBotCore
import Sparkle

@main
struct CrateBotApp: App {
    @State private var appState = AppState()
    @State private var updateManager = UpdateManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([CachedFeatures.self, TagOverride.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(updateManager)
                .modelContainer(sharedModelContainer)
                .onAppear {
                    // Check for updates on launch (silent)
                    updateManager.checkForUpdatesInBackground()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            // Add Check for Updates menu item
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updateManager.checkForUpdates()
                }
            }
        }
    }
}
```

**Step 4: Commit**

```bash
git add CrateBot/App/UpdateManager.swift CrateBot/App/CrateBotApp.swift
git commit -m "feat: integrate Sparkle 2.x for auto-updates

- UpdateManager observable for update state
- Background update checks on launch
- Check for Updates menu item"
```

---

### Task 12.3: DMG/Installer Creation

**Files:**
- Create: `scripts/create-dmg.sh`
- Create: `scripts/dmg-background.png` (placeholder)

**Step 1: Create DMG script**

Create `scripts/create-dmg.sh`:

```bash
#!/bin/bash
set -e

# CrateBot DMG Creator
# Usage: ./scripts/create-dmg.sh <path-to-app> [output-dir]

APP_PATH="${1:?Usage: $0 <path-to-app> [output-dir]}"
OUTPUT_DIR="${2:-build/release}"
APP_NAME=$(basename "$APP_PATH" .app)
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
DMG_NAME="${APP_NAME}-${VERSION}"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}.dmg"

echo "=== Creating CrateBot DMG ==="
echo "App: $APP_PATH"
echo "Version: $VERSION"
echo "Output: $DMG_PATH"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check for create-dmg tool
if ! command -v create-dmg &> /dev/null; then
    echo "Installing create-dmg..."
    brew install create-dmg
fi

# Create DMG
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKGROUND="${SCRIPT_DIR}/dmg-background.png"

create-dmg \
    --volname "CrateBot" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "CrateBot.app" 150 190 \
    --hide-extension "CrateBot.app" \
    --app-drop-link 450 190 \
    ${BACKGROUND:+--background "$BACKGROUND"} \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

echo ""
echo "=== DMG Created ==="
echo "Output: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"

# Notarize DMG if environment is set
if [[ -n "$APPLE_ID" ]]; then
    echo ""
    echo "Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait

    xcrun stapler staple "$DMG_PATH"
    echo "DMG notarized and stapled."
fi
```

**Step 2: Create placeholder background**

Create `scripts/dmg-background.png` - a 600x400 PNG with app branding. For now, we'll skip this and the script handles its absence.

**Step 3: Make executable and commit**

```bash
chmod +x scripts/create-dmg.sh
git add scripts/create-dmg.sh
git commit -m "feat: add DMG creation script

- create-dmg.sh for installer packaging
- Auto-notarization if credentials are set
- Custom window layout for drag-to-install"
```

---

## Checkpoint: Phases 10-12 Complete

### Summary

| Phase | Task | Description | Status |
|-------|------|-------------|--------|
| **10** | 10.1 | ID3 Tag Reading/Writing | Ready |
| **10** | 10.2 | Vibe Generation (Anthropic) | Ready |
| **10** | 10.3 | Hook Detection (WhisperKit) | Ready |
| **11** | 11.1 | Legacy Data Import | Ready |
| **11** | 11.2 | CoreML Model Conversion | Ready |
| **12** | 12.1 | App Notarization | Ready |
| **12** | 12.2 | Sparkle Updates | Ready |
| **12** | 12.3 | DMG Creation | Ready |

### Key Dependencies Added

- **ID3TagEditor** (SPM) - Native Swift ID3 handling
- **Sparkle 2.x** (SPM) - Auto-update framework

### New Modules

- `CrateBotCore/Tags/` - ID3Manager, TagMapping
- `CrateBotCore/Networking/` - HTTPClient, BackendAPI
- `CrateBotCore/Integrations/` - VibeGenerator, HookDetector
- `CrateBotCore/Data/` - LegacyImporter, LegacyModels
- `CrateBotCore/ML/` - ModelManager, ModelMetadata

### Scripts

- `scripts/notarize.sh` - Apple notarization workflow
- `scripts/create-dmg.sh` - DMG installer creation

---

## How to Execute

1. **Use subagent-driven-development** to implement task-by-task
2. Each task follows TDD: write test → implement → verify → commit
3. Review at checkpoints between phases
