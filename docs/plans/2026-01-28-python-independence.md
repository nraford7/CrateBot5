# Python Independence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove all Python backend dependencies from the Swift app, making it fully standalone.

**Architecture:** Replace Python HTTP proxy pattern with direct API calls (Anthropic) and native Apple frameworks (Speech). Delete dead code (HookDetector calls non-existent endpoint). The Swift app already has native ML training, audio analysis, and tag management - we're only removing the backend communication layer.

**Tech Stack:** Swift 5.9+, URLSession, Speech.framework, Keychain Services

---

## Overview

### Current State (Python Dependencies)
```
Swift App
├── VibeGenerator.swift → HTTP → Python → Anthropic API
├── HookDetector.swift → HTTP → Python (BROKEN - endpoint missing!)
├── HTTPClient.swift → Port 8742 communication
└── BackendAPI.swift → Pydantic model mirrors
```

### Target State (Python-Free)
```
Swift App
├── AnthropicClient.swift → Direct Anthropic API
├── NativeVibeGenerator.swift → Uses AnthropicClient
├── NativeHookDetector.swift → Apple Speech.framework
└── (HTTPClient/BackendAPI deleted)
```

### Files to Create
1. `CrateBotCore/Sources/CrateBotCore/Networking/AnthropicClient.swift`
2. `CrateBotCore/Sources/CrateBotCore/Integrations/NativeVibeGenerator.swift`
3. `CrateBotCore/Sources/CrateBotCore/Integrations/NativeHookDetector.swift`
4. `CrateBotCore/Tests/CrateBotCoreTests/Networking/AnthropicClientTests.swift`
5. `CrateBotCore/Tests/CrateBotCoreTests/Integrations/NativeVibeGeneratorTests.swift`
6. `CrateBotCore/Tests/CrateBotCoreTests/Integrations/NativeHookDetectorTests.swift`

### Files to Delete
1. `CrateBotCore/Sources/CrateBotCore/Networking/HTTPClient.swift`
2. `CrateBotCore/Sources/CrateBotCore/Networking/BackendAPI.swift`
3. `CrateBotCore/Sources/CrateBotCore/Integrations/VibeGenerator.swift`
4. `CrateBotCore/Sources/CrateBotCore/Integrations/HookDetector.swift`
5. `CrateBotCore/Tests/CrateBotCoreTests/Integrations/VibeGeneratorTests.swift`
6. `CrateBotCore/Tests/CrateBotCoreTests/Integrations/HookDetectorTests.swift`

---

## Task 1: Create Anthropic API Client

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Networking/AnthropicClient.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/Networking/AnthropicClientTests.swift`

### Step 1: Write the failing test

```swift
// AnthropicClientTests.swift
import XCTest
@testable import CrateBotCore

final class AnthropicClientTests: XCTestCase {

    func testMessageRequestEncoding() throws {
        let request = AnthropicClient.MessageRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 1024,
            messages: [
                .init(role: "user", content: "Hello")
            ]
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-20250514")
        XCTAssertEqual(json["max_tokens"] as? Int, 1024)
        XCTAssertNotNil(json["messages"])
    }

    func testMessageResponseDecoding() throws {
        let json = """
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Hello!"}],
            "model": "claude-sonnet-4-20250514",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 5}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(AnthropicClient.MessageResponse.self, from: json)

        XCTAssertEqual(response.id, "msg_123")
        XCTAssertEqual(response.content.first?.text, "Hello!")
        XCTAssertEqual(response.stopReason, "end_turn")
    }

    func testClientInitializationWithoutAPIKey() {
        // Clear any existing key for test
        try? KeychainManager.shared.delete(key: .anthropicAPIKey)

        let client = AnthropicClient()
        XCTAssertFalse(client.hasAPIKey)
    }
}
```

### Step 2: Run test to verify it fails

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter AnthropicClientTests 2>&1 | head -50`
Expected: FAIL with "AnthropicClient not found"

### Step 3: Write minimal implementation

```swift
// AnthropicClient.swift
import Foundation
import os.log

/// Errors from Anthropic API calls
public enum AnthropicError: Error, LocalizedError, Sendable {
    case apiKeyNotConfigured
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case networkError(String)
    case decodingFailed(String)
    case rateLimited(retryAfter: Int?)

    public var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Anthropic API key not configured"
        case .invalidResponse:
            return "Invalid response from Anthropic API"
        case .requestFailed(let code, let message):
            return "API request failed (\(code)): \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(seconds) seconds"
            }
            return "Rate limited"
        }
    }
}

/// Direct client for Anthropic Claude API
public actor AnthropicClient {

    // MARK: - API Types

    public struct Message: Codable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct MessageRequest: Codable, Sendable {
        public let model: String
        public let maxTokens: Int
        public let messages: [Message]
        public let system: String?

        public init(
            model: String = "claude-sonnet-4-20250514",
            maxTokens: Int = 1024,
            messages: [Message],
            system: String? = nil
        ) {
            self.model = model
            self.maxTokens = maxTokens
            self.messages = messages
            self.system = system
        }
    }

    public struct ContentBlock: Codable, Sendable {
        public let type: String
        public let text: String?
    }

    public struct Usage: Codable, Sendable {
        public let inputTokens: Int
        public let outputTokens: Int
    }

    public struct MessageResponse: Codable, Sendable {
        public let id: String
        public let type: String
        public let role: String
        public let content: [ContentBlock]
        public let model: String
        public let stopReason: String?
        public let usage: Usage

        /// Extract text content from response
        public var text: String {
            content.compactMap { $0.text }.joined()
        }
    }

    public struct ErrorResponse: Codable, Sendable {
        public let type: String
        public let error: ErrorDetail

        public struct ErrorDetail: Codable, Sendable {
            public let type: String
            public let message: String
        }
    }

    // MARK: - Properties

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.cratebot", category: "AnthropicClient")

    public nonisolated var hasAPIKey: Bool {
        KeychainManager.shared.exists(key: .anthropicAPIKey)
    }

    // MARK: - Init

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - API Methods

    /// Send a message to Claude and get a response
    public func sendMessage(_ request: MessageRequest) async throws -> MessageResponse {
        guard let apiKey = KeychainManager.shared.retrieve(key: .anthropicAPIKey) else {
            throw AnthropicError.apiKeyNotConfigured
        }

        var urlRequest = URLRequest(url: Self.apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw AnthropicError.networkError("Failed to encode request: \(error)")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AnthropicError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        logger.debug("Anthropic API response: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            do {
                return try decoder.decode(MessageResponse.self, from: data)
            } catch {
                logger.error("Decoding failed: \(error)")
                throw AnthropicError.decodingFailed(error.localizedDescription)
            }

        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap { Int($0) }
            throw AnthropicError.rateLimited(retryAfter: retryAfter)

        default:
            let errorMessage: String
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                errorMessage = errorResponse.error.message
            } else {
                errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            throw AnthropicError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: errorMessage
            )
        }
    }

    /// Convenience method for simple text prompts
    public func complete(
        prompt: String,
        system: String? = nil,
        model: String = "claude-sonnet-4-20250514",
        maxTokens: Int = 1024
    ) async throws -> String {
        let request = MessageRequest(
            model: model,
            maxTokens: maxTokens,
            messages: [Message(role: "user", content: prompt)],
            system: system
        )
        let response = try await sendMessage(request)
        return response.text
    }
}
```

### Step 4: Run test to verify it passes

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter AnthropicClientTests`
Expected: PASS

### Step 5: Commit

```bash
git add CrateBotCore/Sources/CrateBotCore/Networking/AnthropicClient.swift
git add CrateBotCore/Tests/CrateBotCoreTests/Networking/AnthropicClientTests.swift
git commit -m "feat: add direct Anthropic API client

Replaces Python backend proxy with direct API calls.
- URLSession-based async/await client
- Codable request/response types
- Keychain integration for API key storage
- Rate limit handling"
```

---

## Task 2: Create Native Vibe Generator

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Integrations/NativeVibeGenerator.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/NativeVibeGeneratorTests.swift`

### Step 1: Write the failing test

```swift
// NativeVibeGeneratorTests.swift
import XCTest
@testable import CrateBotCore

final class NativeVibeGeneratorTests: XCTestCase {

    func testVibeContextFormatting() {
        let context = NativeVibeGenerator.VibeContext(
            tempo: 128.0,
            energy: 0.75,
            danceability: 0.85,
            mood: "energetic",
            genre: "House",
            key: "Am",
            hasVocals: true
        )

        let formatted = context.formatted

        XCTAssertTrue(formatted.contains("128"))
        XCTAssertTrue(formatted.contains("House"))
        XCTAssertTrue(formatted.contains("energetic"))
    }

    func testVibePromptGeneration() {
        let context = NativeVibeGenerator.VibeContext(
            tempo: 120.0,
            energy: 0.6,
            danceability: 0.7,
            mood: "chill",
            genre: "Deep House",
            key: "Cm",
            hasVocals: false
        )

        let prompt = NativeVibeGenerator.buildPrompt(context: context)

        XCTAssertTrue(prompt.contains("Deep House"))
        XCTAssertTrue(prompt.contains("VIBE:"))
    }

    func testVibeResponseParsing() {
        let response = """
        Based on the audio analysis:

        VIBE: Late Night Groove

        This track has a deep, hypnotic quality perfect for after-hours sets.
        """

        let vibe = NativeVibeGenerator.parseVibeFromResponse(response)

        XCTAssertEqual(vibe, "Late Night Groove")
    }

    func testVibeResponseParsingNoMatch() {
        let response = "This is just a regular response without the expected format."

        let vibe = NativeVibeGenerator.parseVibeFromResponse(response)

        XCTAssertNil(vibe)
    }
}
```

### Step 2: Run test to verify it fails

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter NativeVibeGeneratorTests 2>&1 | head -50`
Expected: FAIL with "NativeVibeGenerator not found"

### Step 3: Write minimal implementation

```swift
// NativeVibeGenerator.swift
import Foundation
import os.log

/// Errors during vibe generation
public enum NativeVibeError: Error, LocalizedError, Sendable {
    case apiKeyNotConfigured
    case generationFailed(String)
    case parsingFailed
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Anthropic API key not configured. Add it in Settings."
        case .generationFailed(let message):
            return "Vibe generation failed: \(message)"
        case .parsingFailed:
            return "Could not parse vibe from response"
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        }
    }
}

/// Native vibe generator using direct Anthropic API calls
public actor NativeVibeGenerator {

    // MARK: - Types

    /// Audio context for vibe generation
    public struct VibeContext: Sendable {
        public let tempo: Double
        public let energy: Double
        public let danceability: Double
        public let mood: String
        public let genre: String
        public let key: String
        public let hasVocals: Bool
        public let additionalTags: [String]

        public init(
            tempo: Double,
            energy: Double,
            danceability: Double,
            mood: String,
            genre: String,
            key: String = "Unknown",
            hasVocals: Bool = false,
            additionalTags: [String] = []
        ) {
            self.tempo = tempo
            self.energy = energy
            self.danceability = danceability
            self.mood = mood
            self.genre = genre
            self.key = key
            self.hasVocals = hasVocals
            self.additionalTags = additionalTags
        }

        /// Format context for prompt inclusion
        public var formatted: String {
            var lines: [String] = []
            lines.append("Tempo: \(Int(tempo)) BPM")
            lines.append("Genre: \(genre)")
            lines.append("Mood: \(mood)")
            lines.append("Energy: \(Int(energy * 100))%")
            lines.append("Danceability: \(Int(danceability * 100))%")
            lines.append("Key: \(key)")
            lines.append("Vocals: \(hasVocals ? "Yes" : "No/Instrumental")")
            if !additionalTags.isEmpty {
                lines.append("Tags: \(additionalTags.joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Result of vibe generation
    public struct VibeResult: Sendable {
        public let vibe: String
        public let description: String?
        public let cached: Bool

        public init(vibe: String, description: String? = nil, cached: Bool = false) {
            self.vibe = vibe
            self.description = description
            self.cached = cached
        }
    }

    // MARK: - Properties

    private let anthropicClient: AnthropicClient
    private let logger = Logger(subsystem: "com.cratebot", category: "NativeVibeGenerator")
    private var cache: [String: VibeResult] = [:]

    // MARK: - Init

    public init(anthropicClient: AnthropicClient? = nil) {
        self.anthropicClient = anthropicClient ?? AnthropicClient()
    }

    // MARK: - Public API

    /// Check if vibe generation is available (API key configured)
    public nonisolated var isAvailable: Bool {
        KeychainManager.shared.exists(key: .anthropicAPIKey)
    }

    /// Generate a vibe tag for audio with the given context
    public func generateVibe(
        context: VibeContext,
        cacheKey: String? = nil
    ) async throws -> VibeResult {
        // Check cache first
        if let key = cacheKey, let cached = cache[key] {
            logger.debug("Returning cached vibe for \(key)")
            return VibeResult(vibe: cached.vibe, description: cached.description, cached: true)
        }

        guard isAvailable else {
            throw NativeVibeError.apiKeyNotConfigured
        }

        let prompt = Self.buildPrompt(context: context)
        let systemPrompt = Self.systemPrompt

        logger.info("Generating vibe for \(context.genre) track at \(Int(context.tempo)) BPM")

        do {
            let response = try await anthropicClient.complete(
                prompt: prompt,
                system: systemPrompt,
                maxTokens: 256
            )

            guard let vibe = Self.parseVibeFromResponse(response) else {
                logger.warning("Could not parse VIBE from response")
                throw NativeVibeError.parsingFailed
            }

            let result = VibeResult(vibe: vibe, description: response, cached: false)

            // Cache the result
            if let key = cacheKey {
                cache[key] = result
            }

            logger.info("Generated vibe: \(vibe)")
            return result

        } catch let error as AnthropicError {
            switch error {
            case .apiKeyNotConfigured:
                throw NativeVibeError.apiKeyNotConfigured
            default:
                throw NativeVibeError.generationFailed(error.localizedDescription)
            }
        }
    }

    /// Clear the vibe cache
    public func clearCache() {
        cache.removeAll()
        logger.info("Vibe cache cleared")
    }

    // MARK: - Prompt Building

    static let systemPrompt = """
    You are a DJ's assistant that creates short, evocative "vibe" tags for music tracks.
    A vibe tag is 2-4 words that capture the feeling/atmosphere of a track.

    Good vibe examples: "Late Night Groove", "Peak Time Energy", "Sunset Terrace",
    "Dark Warehouse", "Sunday Morning", "Festival Main Stage"

    Bad vibes (too generic): "Good Song", "Nice Beat", "Dance Music"

    Always respond with VIBE: followed by your vibe tag on its own line.
    """

    static func buildPrompt(context: VibeContext) -> String {
        """
        Analyze this track and give me a vibe tag:

        \(context.formatted)

        Based on these characteristics, what's the vibe? When/where would a DJ play this?

        Respond with VIBE: followed by a 2-4 word vibe tag.
        """
    }

    // MARK: - Response Parsing

    static func parseVibeFromResponse(_ response: String) -> String? {
        // Look for "VIBE:" pattern
        let pattern = #"VIBE:\s*(.+?)(?:\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: response,
                range: NSRange(response.startIndex..., in: response)
              ),
              let vibeRange = Range(match.range(at: 1), in: response) else {
            return nil
        }

        let vibe = String(response[vibeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return vibe.isEmpty ? nil : vibe
    }
}
```

### Step 4: Run test to verify it passes

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter NativeVibeGeneratorTests`
Expected: PASS

### Step 5: Commit

```bash
git add CrateBotCore/Sources/CrateBotCore/Integrations/NativeVibeGenerator.swift
git add CrateBotCore/Tests/CrateBotCoreTests/Integrations/NativeVibeGeneratorTests.swift
git commit -m "feat: add native vibe generator with direct Anthropic API

- VibeContext struct for audio characteristics
- Direct Claude API calls via AnthropicClient
- VIBE: response parsing
- In-memory caching support"
```

---

## Task 3: Create Native Hook Detector

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Integrations/NativeHookDetector.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/NativeHookDetectorTests.swift`

### Step 1: Write the failing test

```swift
// NativeHookDetectorTests.swift
import XCTest
@testable import CrateBotCore

final class NativeHookDetectorTests: XCTestCase {

    func testHookResultInitialization() {
        let result = NativeHookDetector.HookResult(
            hook: "Feel the rhythm",
            confidence: 0.85,
            occurrences: 3
        )

        XCTAssertEqual(result.hook, "Feel the rhythm")
        XCTAssertEqual(result.confidence, 0.85)
        XCTAssertEqual(result.occurrences, 3)
        XCTAssertTrue(result.hasHook)
    }

    func testHookResultNoHook() {
        let result = NativeHookDetector.HookResult(
            hook: nil,
            confidence: 0.0,
            occurrences: 0
        )

        XCTAssertNil(result.hook)
        XCTAssertFalse(result.hasHook)
    }

    func testHookResultLowConfidence() {
        let result = NativeHookDetector.HookResult(
            hook: "Maybe this",
            confidence: 0.3,
            occurrences: 1
        )

        XCTAssertFalse(result.hasHook) // Below 0.5 threshold
    }

    func testPhraseExtractionFromTranscription() {
        let transcription = "Feel the rhythm feel the beat feel the rhythm of the night"

        let phrases = NativeHookDetector.extractRepeatedPhrases(from: transcription)

        // "feel the rhythm" appears twice
        XCTAssertTrue(phrases.contains { $0.phrase.lowercased().contains("feel the rhythm") })
    }

    func testPhraseExtractionNoRepeats() {
        let transcription = "This is a unique sentence with no repeated phrases at all"

        let phrases = NativeHookDetector.extractRepeatedPhrases(from: transcription)

        XCTAssertTrue(phrases.isEmpty)
    }
}
```

### Step 2: Run test to verify it fails

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter NativeHookDetectorTests 2>&1 | head -50`
Expected: FAIL with "NativeHookDetector not found"

### Step 3: Write minimal implementation

```swift
// NativeHookDetector.swift
import Foundation
import Speech
import AVFoundation
import os.log

/// Errors during hook detection
public enum NativeHookError: Error, LocalizedError, Sendable {
    case speechRecognitionUnavailable
    case authorizationDenied
    case noVocalsDetected
    case transcriptionFailed(String)
    case fileNotFound(String)
    case audioLoadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this device"
        case .authorizationDenied:
            return "Speech recognition permission denied"
        case .noVocalsDetected:
            return "No vocals detected in track"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .audioLoadFailed(let message):
            return "Failed to load audio: \(message)"
        }
    }
}

/// Native hook detector using Apple Speech framework
public actor NativeHookDetector {

    // MARK: - Types

    /// Result of hook detection
    public struct HookResult: Sendable {
        public let hook: String?
        public let confidence: Double
        public let occurrences: Int
        public let transcription: String?

        public var hasHook: Bool {
            hook != nil && confidence >= 0.5
        }

        public init(
            hook: String?,
            confidence: Double,
            occurrences: Int,
            transcription: String? = nil
        ) {
            self.hook = hook
            self.confidence = confidence
            self.occurrences = occurrences
            self.transcription = transcription
        }
    }

    /// A detected phrase with its occurrence count
    public struct DetectedPhrase: Sendable {
        public let phrase: String
        public let count: Int
        public let confidence: Double
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cratebot", category: "NativeHookDetector")
    private var cache: [String: HookResult] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Check if speech recognition is available
    public nonisolated var isAvailable: Bool {
        SFSpeechRecognizer.isAvailable
    }

    /// Request speech recognition authorization
    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Detect hook in audio file
    public func detectHook(
        in fileURL: URL,
        cacheKey: String? = nil
    ) async throws -> HookResult {
        // Check cache
        if let key = cacheKey, let cached = cache[key] {
            logger.debug("Returning cached hook for \(key)")
            return cached
        }

        // Validate file
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NativeHookError.fileNotFound(fileURL.path)
        }

        // Check authorization
        guard await requestAuthorization() else {
            throw NativeHookError.authorizationDenied
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw NativeHookError.speechRecognitionUnavailable
        }

        logger.info("Starting transcription for: \(fileURL.lastPathComponent)")

        // Transcribe audio
        let transcription = try await transcribe(fileURL: fileURL, recognizer: recognizer)

        guard !transcription.isEmpty else {
            let result = HookResult(hook: nil, confidence: 0, occurrences: 0, transcription: nil)
            if let key = cacheKey { cache[key] = result }
            return result
        }

        // Extract repeated phrases
        let phrases = Self.extractRepeatedPhrases(from: transcription)

        // Find best hook candidate
        let result: HookResult
        if let best = phrases.first {
            result = HookResult(
                hook: best.phrase,
                confidence: best.confidence,
                occurrences: best.count,
                transcription: transcription
            )
            logger.info("Detected hook: \"\(best.phrase)\" (confidence: \(best.confidence))")
        } else {
            result = HookResult(
                hook: nil,
                confidence: 0,
                occurrences: 0,
                transcription: transcription
            )
            logger.debug("No repeated phrases found")
        }

        if let key = cacheKey { cache[key] = result }
        return result
    }

    /// Clear the hook cache
    public func clearCache() {
        cache.removeAll()
        logger.info("Hook cache cleared")
    }

    // MARK: - Transcription

    private func transcribe(
        fileURL: URL,
        recognizer: SFSpeechRecognizer
    ) async throws -> String {
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: NativeHookError.transcriptionFailed(error.localizedDescription))
                    return
                }

                guard let result = result, result.isFinal else { return }

                let transcription = result.bestTranscription.formattedString
                continuation.resume(returning: transcription)
            }
        }
    }

    // MARK: - Phrase Extraction

    /// Extract repeated phrases from transcription
    public static func extractRepeatedPhrases(from text: String) -> [DetectedPhrase] {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard words.count >= 3 else { return [] }

        var phraseCounts: [String: Int] = [:]

        // Look for 3-6 word phrases
        for length in 3...min(6, words.count) {
            for i in 0...(words.count - length) {
                let phrase = words[i..<(i + length)].joined(separator: " ")
                phraseCounts[phrase, default: 0] += 1
            }
        }

        // Filter to repeated phrases only (2+ occurrences)
        let repeated = phraseCounts
            .filter { $0.value >= 2 }
            .map { phrase, count in
                // Confidence based on repetition and phrase quality
                let lengthBonus = Double(phrase.split(separator: " ").count) / 6.0
                let repetitionBonus = min(Double(count) / 4.0, 1.0)
                let confidence = (lengthBonus + repetitionBonus) / 2.0

                return DetectedPhrase(
                    phrase: phrase.capitalized,
                    count: count,
                    confidence: confidence
                )
            }
            .sorted { $0.confidence > $1.confidence }

        return Array(repeated.prefix(5))
    }
}
```

### Step 4: Run test to verify it passes

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test --filter NativeHookDetectorTests`
Expected: PASS

### Step 5: Commit

```bash
git add CrateBotCore/Sources/CrateBotCore/Integrations/NativeHookDetector.swift
git add CrateBotCore/Tests/CrateBotCoreTests/Integrations/NativeHookDetectorTests.swift
git commit -m "feat: add native hook detector using Apple Speech framework

- SFSpeechRecognizer for audio transcription
- N-gram phrase extraction algorithm
- Confidence scoring based on repetition
- In-memory caching support
- No Python backend dependency"
```

---

## Task 4: Delete Old Python-Dependent Code

**Files:**
- Delete: `CrateBotCore/Sources/CrateBotCore/Networking/HTTPClient.swift`
- Delete: `CrateBotCore/Sources/CrateBotCore/Networking/BackendAPI.swift`
- Delete: `CrateBotCore/Sources/CrateBotCore/Integrations/VibeGenerator.swift`
- Delete: `CrateBotCore/Sources/CrateBotCore/Integrations/HookDetector.swift`
- Delete: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/VibeGeneratorTests.swift`
- Delete: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/HookDetectorTests.swift`

### Step 1: Verify tests pass before deletion

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test 2>&1 | tail -20`
Expected: All tests pass

### Step 2: Delete old files

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore

# Delete old networking files
rm Sources/CrateBotCore/Networking/HTTPClient.swift
rm Sources/CrateBotCore/Networking/BackendAPI.swift

# Delete old integration files
rm Sources/CrateBotCore/Integrations/VibeGenerator.swift
rm Sources/CrateBotCore/Integrations/HookDetector.swift

# Delete old tests
rm Tests/CrateBotCoreTests/Integrations/VibeGeneratorTests.swift
rm Tests/CrateBotCoreTests/Integrations/HookDetectorTests.swift
```

### Step 3: Verify build still succeeds

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift build 2>&1 | tail -20`
Expected: Build succeeded

### Step 4: Run tests to confirm

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test 2>&1 | tail -20`
Expected: All tests pass

### Step 5: Commit

```bash
git add -A
git commit -m "chore: remove Python backend dependencies

BREAKING CHANGE: Removed HTTPClient and BackendAPI.

Deleted:
- HTTPClient.swift (Python proxy client)
- BackendAPI.swift (Pydantic model mirrors)
- VibeGenerator.swift (Python-dependent)
- HookDetector.swift (called non-existent endpoint)
- Associated test files

Replaced by:
- AnthropicClient.swift (direct API)
- NativeVibeGenerator.swift
- NativeHookDetector.swift"
```

---

## Task 5: Update CrateBot App to Use Native Implementations

**Files:**
- Modify: `CrateBot/App/AppState.swift` (if references VibeGenerator)
- Modify: Any views that use VibeGenerator or HookDetector

### Step 1: Search for usages

Run: `grep -r "VibeGenerator\|HookDetector\|HTTPClient\|BackendAPI" /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBot/ --include="*.swift" | grep -v ".build"`
Expected: List of files needing updates

### Step 2: Update each file

For each file found, replace:
- `VibeGenerator` → `NativeVibeGenerator`
- `HookDetector` → `NativeHookDetector`
- Remove `HTTPClient` references
- Remove `BackendAPI` references

### Step 3: Verify Xcode build succeeds

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && xcodebuild -scheme CrateBot -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

### Step 4: Commit

```bash
git add -A
git commit -m "refactor: update CrateBot app to use native implementations

- Replace VibeGenerator with NativeVibeGenerator
- Replace HookDetector with NativeHookDetector
- Remove all Python backend references"
```

---

## Task 6: Final Verification & Cleanup

### Step 1: Verify no Python references remain

Run: `grep -r "8742\|/api/v1\|HTTPClient\|BackendAPI" /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore/ --include="*.swift" | grep -v ".build"`
Expected: No matches

Run: `grep -r "8742\|/api/v1\|HTTPClient\|BackendAPI" /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBot/ --include="*.swift"`
Expected: No matches

### Step 2: Run full test suite

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore && swift test`
Expected: All tests pass

### Step 3: Build CrateBot app

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && xcodebuild -scheme CrateBot -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

### Step 4: Create final commit

```bash
git add -A
git commit -m "chore: complete Python independence migration

The Swift app is now fully standalone:
- Direct Anthropic API calls for vibe generation
- Native Apple Speech framework for hook detection
- All Python backend code can be safely removed

No external server required to run the app."
```

---

## Summary

After completing all tasks, the Swift app will be **100% Python-free**:

| Feature | Before | After |
|---------|--------|-------|
| Vibe Generation | Swift → HTTP → Python → Anthropic | Swift → Anthropic |
| Hook Detection | Swift → HTTP → Python (broken) | Swift → Speech.framework |
| Audio Analysis | Already native | Already native |
| ML Training | Already native | Already native |
| Tag Management | Already native | Already native |

**Total files deleted:** 6
**Total files created:** 6
**Net change:** 0 files, cleaner architecture
