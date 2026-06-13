import Foundation
import os.log

// MARK: - Error Types

/// Errors that can occur during native vibe generation
public enum NativeVibeError: Error, LocalizedError, Sendable {
    case apiKeyNotConfigured
    case generationFailed(String)
    case parsingFailed
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Anthropic API key is not configured"
        case .generationFailed(let message):
            return "Vibe generation failed: \(message)"
        case .parsingFailed:
            return "Failed to parse vibe from API response"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

// MARK: - Data Types

/// Context about a track used to generate a vibe
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
        key: String,
        hasVocals: Bool,
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

    /// Formatted string representation of the context for use in prompts
    public var formatted: String {
        var lines: [String] = []
        lines.append("Genre: \(genre)")
        lines.append("Tempo: \(String(format: "%.1f", tempo)) BPM")
        lines.append("Key: \(key)")
        lines.append("Mood: \(mood)")
        lines.append("Energy: \(String(format: "%.2f", energy))")
        lines.append("Danceability: \(String(format: "%.2f", danceability))")
        lines.append("Has Vocals: \(hasVocals ? "Yes" : "No")")

        if !additionalTags.isEmpty {
            lines.append("Additional Tags: \(additionalTags.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

/// Result of native vibe generation
public struct NativeVibeResult: Sendable {
    public let vibe: String
    public let description: String?
    public let cached: Bool

    public init(
        vibe: String,
        description: String? = nil,
        cached: Bool = false
    ) {
        self.vibe = vibe
        self.description = description
        self.cached = cached
    }
}

// MARK: - Native Vibe Generator

/// Actor for generating AI-powered vibe tags directly via Anthropic API
@available(*, deprecated, message: "Use VibeGeneratorV2")
public actor NativeVibeGenerator {
    private let client: AnthropicClient
    private var cache: [String: NativeVibeResult] = [:]
    private let logger = Logger(subsystem: "com.cratebot", category: "NativeVibeGenerator")

    /// Initialize with an optional AnthropicClient
    /// - Parameter client: The Anthropic client to use. If nil, creates a new one.
    public init(client: AnthropicClient? = nil) {
        self.client = client ?? AnthropicClient()
    }

    /// Check if vibe generation is available (nonisolated for synchronous access)
    public nonisolated var isAvailable: Bool {
        KeychainManager.shared.exists(key: .anthropicAPIKey)
    }

    /// Generate a vibe for the given context
    /// - Parameters:
    ///   - context: The vibe context describing the track
    ///   - cacheKey: Optional key for caching. If provided and cached, returns cached result.
    /// - Returns: The generated vibe result
    public func generateVibe(context: VibeContext, cacheKey: String? = nil) async throws -> NativeVibeResult {
        // Check cache first
        if let key = cacheKey, let cached = cache[key] {
            logger.debug("Returning cached vibe for key: \(key)")
            return NativeVibeResult(vibe: cached.vibe, description: cached.description, cached: true)
        }

        // Verify API key is available
        guard isAvailable else {
            logger.error("API key not configured")
            throw NativeVibeError.apiKeyNotConfigured
        }

        logger.info("Generating vibe for: \(context.genre) | \(context.tempo) BPM | \(context.mood)")

        // Build the prompt
        let prompt = Self.buildPrompt(context: context)

        // Call the API
        let response: String
        do {
            response = try await client.complete(
                prompt: prompt,
                system: Self.systemPrompt,
                maxTokens: 256
            )
        } catch let error as AnthropicError {
            logger.error("API error: \(error.localizedDescription)")
            throw NativeVibeError.generationFailed(error.localizedDescription)
        } catch {
            logger.error("Unexpected error: \(error.localizedDescription)")
            throw NativeVibeError.generationFailed(error.localizedDescription)
        }

        // Parse the vibe from the response
        guard let vibe = Self.parseVibeFromResponse(response) else {
            logger.error("Failed to parse vibe from response: \(response)")
            throw NativeVibeError.parsingFailed
        }

        logger.info("Generated vibe: \(vibe)")

        let result = NativeVibeResult(vibe: vibe, description: nil, cached: false)

        // Cache the result if a key was provided
        if let key = cacheKey {
            cache[key] = result
            logger.debug("Cached vibe for key: \(key)")
        }

        return result
    }

    /// Clear the in-memory cache
    public func clearCache() {
        cache.removeAll()
        logger.info("Cache cleared")
    }

    // MARK: - Static Methods

    /// The system prompt for Claude when generating vibes
    public static var systemPrompt: String {
        """
        You are a DJ and music curator expert. Your task is to generate a short, evocative "vibe" label \
        for electronic music tracks based on their audio characteristics.

        A vibe should be 2-4 words that capture the feel, energy, and appropriate setting for the track. \
        Think about when and where this track would be played - time of day, venue type, crowd mood.

        Examples of good vibes:
        - "Late Night Groove"
        - "Peak Time Banger"
        - "Sunset Terrace"
        - "After Hours Hypnotic"
        - "Morning Warmup"
        - "Festival Main Stage"
        - "Underground Warehouse"
        - "Poolside Chill"

        Always output your response in this exact format:
        VIBE: [Your vibe here]

        Keep it concise and evocative. The vibe should immediately convey the track's character to a DJ.
        """
    }

    /// Build the user prompt from the given context
    /// - Parameter context: The vibe context
    /// - Returns: The formatted prompt string
    public static func buildPrompt(context: VibeContext) -> String {
        """
        Generate a vibe for this track based on its characteristics:

        \(context.formatted)

        Based on these characteristics, what vibe would you assign to this track? \
        Remember to output your answer in the format: VIBE: [your vibe]
        """
    }

    /// Parse the vibe from an API response
    /// - Parameter response: The raw API response text
    /// - Returns: The extracted vibe, or nil if not found
    public static func parseVibeFromResponse(_ response: String) -> String? {
        // Look for "VIBE:" pattern (case-insensitive to handle model variations)
        let pattern = "(?i)VIBE:\\s*(.+?)(?:\\n|$)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                  in: response,
                  options: [],
                  range: NSRange(response.startIndex..., in: response)
              ),
              let vibeRange = Range(match.range(at: 1), in: response) else {
            return nil
        }

        let vibe = String(response[vibeRange]).trimmingCharacters(in: .whitespaces)
        return vibe.isEmpty ? nil : vibe
    }
}
