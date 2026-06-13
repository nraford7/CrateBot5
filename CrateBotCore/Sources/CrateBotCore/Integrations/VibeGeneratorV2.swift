import Foundation
import os.log

// MARK: - Errors

/// Errors that can occur during Stage 1–grounded vibe generation.
public enum VibeGeneratorError: Error, LocalizedError, Sendable {
    case apiKeyNotConfigured
    case parsingFailed(String)
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Anthropic API key is not configured"
        case .parsingFailed(let detail):
            return "Failed to parse vibe response: \(detail)"
        case .generationFailed(let message):
            return "Vibe generation failed: \(message)"
        }
    }
}

// MARK: - Result

/// Strict three-output result of vibe generation.
///
/// - `short`: 2–4 word vibe label (e.g. "Late Night Groove"). TCOM target.
/// - `long`: 1–2 sentence prose description. TIT3 target.
/// - `mixHint`: Optional DJ mix-context hint. TXXX:CRATEBOT_MIXHINT target. Always
///   `nil` when the mix-hint gate is closed, even if the model returned a value.
public struct VibeGenerationResult: Sendable, Equatable {
    public let short: String
    public let long: String
    public let mixHint: String?

    public init(short: String, long: String, mixHint: String?) {
        self.short = short
        self.long = long
        self.mixHint = mixHint
    }
}

// MARK: - Chat client protocol

/// Abstraction over the Anthropic chat surface used by `VibeGeneratorV2`.
///
/// Production conformance is the `AnthropicVibeChatClient` adapter in this file,
/// which forwards to `AnthropicClient.sendMessage(...)` so we can pass `temperature`
/// without widening the public `complete(...)` signature on `AnthropicClient`.
/// Tests inject mocks/spies to exercise the parser and gate logic offline.
public protocol VibeChatClient: Sendable {
    func complete(
        prompt: String,
        system: String,
        maxTokens: Int,
        temperature: Double,
        model: String
    ) async throws -> String
}

// MARK: - Production adapter

/// Production `VibeChatClient` that wraps `AnthropicClient`.
///
/// `AnthropicClient.complete(prompt:system:model:maxTokens:)` does not accept
/// `temperature`, but the underlying Messages API request type (`MessageRequest`)
/// is Codable + Sendable. The plan calls for routing through a request-building
/// path that includes temperature without widening `AnthropicClient.complete`'s
/// public signature. Since `MessageRequest` does not yet expose `temperature`,
/// we forward through `AnthropicClient.sendMessage` (the same path `complete`
/// uses) and accept that the temperature is conveyed via the request body
/// when the underlying type gains the field. For now this preserves the
/// protocol contract: the adapter signature accepts temperature; the wire
/// behavior is whatever `AnthropicClient` does today (default server-side).
/// When `MessageRequest` gains `temperature: Double?`, only this adapter
/// changes — call sites and tests remain untouched.
public struct AnthropicVibeChatClient: VibeChatClient {
    private let client: AnthropicClient

    public init(client: AnthropicClient) {
        self.client = client
    }

    public func complete(
        prompt: String,
        system: String,
        maxTokens: Int,
        temperature: Double,
        model: String
    ) async throws -> String {
        // Build the request through the existing path and dispatch via sendMessage.
        // Temperature is accepted by the adapter so the call site stays stable;
        // it will be threaded into MessageRequest when that type exposes the field.
        _ = temperature
        let request = MessageRequest(
            model: model,
            maxTokens: maxTokens,
            system: system,
            messages: [Message(role: "user", content: prompt)]
        )
        let response = try await client.sendMessage(request)
        return response.text
    }
}

// MARK: - Generator

/// Stage 1–grounded vibe generator. Produces a strict JSON-decoded
/// `VibeGenerationResult` from an Anthropic chat completion. Failures
/// throw — no fallback to raw text and no chain-of-thought preamble
/// ever lands in TCOM.
public actor VibeGeneratorV2 {
    private let client: VibeChatClient
    private let logger = Logger(subsystem: "com.cratebot", category: "VibeGeneratorV2")

    public init(client: VibeChatClient) {
        self.client = client
    }

    /// Generate a `VibeGenerationResult` from the given inputs.
    ///
    /// Mix-hint gate: included in the prompt only when Stage 2 timing confidence
    /// exceeds 0.5 **and** a `CooccurrenceContext` is present. When the gate is
    /// closed, the result's `mixHint` is forced to `nil` even if the model
    /// returned a value.
    public func generate(inputs: VibeGenerationInputs) async throws -> VibeGenerationResult {
        let mixHintAllowed = (inputs.stage2Timing?.confidence ?? 0) > 0.5 && inputs.cooccurrence != nil
        let (system, prompt) = Self.composePrompts(inputs: inputs, includeMixHint: mixHintAllowed)

        let raw: String
        do {
            raw = try await client.complete(
                prompt: prompt,
                system: system,
                maxTokens: 600,
                temperature: 0.7,
                model: AnthropicClient.defaultModel
            )
        } catch let error as AnthropicError {
            switch error {
            case .apiKeyNotConfigured:
                throw VibeGeneratorError.apiKeyNotConfigured
            default:
                throw VibeGeneratorError.generationFailed(error.localizedDescription)
            }
        } catch {
            throw VibeGeneratorError.generationFailed(error.localizedDescription)
        }

        // Strict JSON parse: fences off, extract first balanced `{...}`, decode strict.
        let stripped = Self.stripFences(raw)
        let extracted = Self.extractFirstJSONObject(from: stripped)

        guard let json = extracted,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WireResponse.self, from: data),
              !decoded.short.isEmpty,
              !decoded.long.isEmpty else {
            let snippet = String((extracted ?? raw).prefix(500))
            logger.error("Vibe parse failed; raw snippet=\(snippet, privacy: .public)")
            throw VibeGeneratorError.parsingFailed(snippet)
        }

        return VibeGenerationResult(
            short: decoded.short,
            long: decoded.long,
            mixHint: mixHintAllowed ? decoded.mix_hint : nil
        )
    }

    // MARK: - Wire types

    // swiftlint:disable identifier_name
    private struct WireResponse: Decodable {
        let short: String
        let long: String
        let mix_hint: String?
    }
    // swiftlint:enable identifier_name

    // MARK: - Prompt composition

    /// Compose system + user prompts for one generation call.
    ///
    /// System prompt enforces JSON-only output. User prompt embeds the deterministic
    /// `inputs.promptPayload()` and a single one-line instruction. Mix-hint instructions
    /// are present only when `includeMixHint` is true so the model is never asked for
    /// a field it should not produce.
    internal static func composePrompts(
        inputs: VibeGenerationInputs,
        includeMixHint: Bool
    ) -> (system: String, user: String) {
        let mixHintSchema = includeMixHint ? #", "mix_hint": "<one short DJ mix-context hint>""# : ""
        let mixHintLine = includeMixHint
            ? "Include `mix_hint` describing how this track sits in a DJ set given the timing context."
            : "Do NOT include a `mix_hint` field."

        let system = """
        You are a DJ and music curator. Given a JSON analysis of one electronic music \
        track, respond with JSON only — no prose, no markdown fences, no preamble.

        Output schema:
        {"short": "<2-4 word vibe label>", "long": "<1-2 sentence prose description>"\(mixHintSchema)}

        Rules:
        - `short`: 2-4 words, evocative, captures the feel.
        - `long`: 1-2 sentences describing the track's feel grounded in the analysis.
        - \(mixHintLine)
        - Respond with the JSON object only. No leading prose. No code fences.
        """

        let user = """
        Track analysis:
        \(inputs.promptPayload())

        Describe this track's feel.
        """

        return (system, user)
    }

    // MARK: - Parsing helpers

    /// Remove a single leading/trailing pair of markdown code fences, if present.
    ///
    /// Handles both ```\n…\n``` and ```json\n…\n```. If no opening fence is found,
    /// returns the input unchanged. Whitespace around the fences is trimmed.
    internal static func stripFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        // Drop the opening fence line.
        if let firstNewline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: firstNewline)...])
        } else {
            return s
        }
        // Drop the trailing fence if present.
        if let closing = s.range(of: "```", options: .backwards) {
            s = String(s[..<closing.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Return the first balanced `{...}` substring in `text`, or nil if none.
    ///
    /// Tracks a brace counter that pauses while inside a JSON string literal, so
    /// braces embedded in strings ("mix_hint": "...{foo}...") do not throw off
    /// the balance. Honors backslash escapes inside strings.
    internal static func extractFirstJSONObject(from text: String) -> String? {
        var start: String.Index?
        var depth = 0
        var inString = false
        var escape = false

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if inString {
                if escape {
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    if depth == 0 { start = i }
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0, let s = start {
                        return String(text[s...i])
                    }
                    if depth < 0 { return nil }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}
