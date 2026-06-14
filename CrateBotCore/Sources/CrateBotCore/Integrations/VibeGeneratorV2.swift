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
public struct VibeGenerationResult: Sendable, Equatable, Codable {
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
/// Threads `temperature` into `MessageRequest` so it lands on the wire as the
/// Anthropic `temperature` field. Dispatches via `AnthropicClient.sendMessage`
/// (the same path used by `AnthropicClient.complete`) without widening the
/// public `complete(...)` signature on `AnthropicClient`.
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
        let request = MessageRequest(
            model: model,
            maxTokens: maxTokens,
            system: system,
            messages: [Message(role: "user", content: prompt)],
            temperature: temperature
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
    /// All three fields are always requested. The prompt instructs the model to
    /// reference the Stage 2 Timing label when present and infer the slot from
    /// BPM + Genre when it is not.
    public func generate(inputs: VibeGenerationInputs) async throws -> VibeGenerationResult {
        let (system, prompt) = Self.composePrompts(inputs: inputs, includeMixHint: true)

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
            mixHint: decoded.mix_hint
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
        let shortForbidden = Self.forbiddenShortTokens(inputs: inputs)
        let shortForbiddenLine = shortForbidden.isEmpty
            ? ""
            : " FORBIDDEN words in `short` for THIS track (do not use, do not pluralize, do not rhyme on): \(shortForbidden.joined(separator: ", "))."

        let system = """
        You are a veteran DJ tagging a record crate. Given a JSON analysis of one \
        electronic music track, respond with JSON only — no prose, no markdown fences, \
        no preamble.

        The three fields are NOT three flavors of the same description. They are three \
        DIFFERENT kinds of sentence. Read each role carefully:

          • `short` — a poetic NICKNAME the DJ can remember in a glance. EXACTLY 4 \
            ALL-CAPS words. Distills the track in FRESH words that DO NOT appear in the \
            track title, artist, genre, mood, or any predicted tag. Never repeats words \
            you used in `long` or `mix_hint`.

          • `long` — describes WHAT THE TRACK SOUNDS LIKE. The instruments you hear, the \
            texture, the rhythm, the production feel. Like a reviewer hearing the record \
            blind. NEVER mentions when to play it, the set, the night, the room, or any \
            DJ action. If a phrase could appear in a DJ instruction sheet, it does not \
            belong here.

          • `mix_hint` — describes HOW TO PLAY THE TRACK. NEVER describes the sound or \
            instruments. NEVER repeats what `long` already said. It is an ORDER to the \
            DJ: when in the set to drop it, what to mix INTO it from, what to follow it \
            with. If a phrase could appear in a music review, it does not belong here.

        Self-check before responding: cover the `long` field — can you reconstruct it \
        from the `mix_hint`? If yes, REWRITE both. They must read as different KINDS \
        of sentence, not different phrasings of the same sentence.

        Output schema:
        {"short": "<EXACTLY 4 CAPS WORDS>", "long": "<one sentence about what it sounds like>", "mix_hint": "<one sentence about how to play it>"}

        Hard rules:
        - `short`: EXACTLY 4 words, ALL CAPS, no articles, no punctuation, no numbers. \
          Every word must be FRESH — not in the track title, artist, genre, mood, tags, \
          `long`, or `mix_hint`.\(shortForbiddenLine) \
          Pair concrete sensation with a poetic or unexpected word. \
          Structure templates (use as scaffolding, NOT word source): \
          [TIME-OF-DAY] [TEXTURE-NOUN] [BODY-VERB] [PLACE-NOUN], or \
          [WEATHER-NOUN] [INSTRUMENT-NOUN] [EMOTION-VERB] [ARCHITECTURE-NOUN].

        - `long`: ONE sentence about SOUND ONLY. Max 16 words. Begin with a noun or \
          adjective. \
          FORBIDDEN in `long` (these are placement/DJ words and belong in `mix_hint`): \
          set, mix, drop, play, DJ, night, peak, room, slot, club, dancefloor, hour, \
          opener, anthem, opening, prime, after, before, into, follow, builds, owns, \
          lifts, banger, early, late, warm-up, peak-time, opener, closer.

        - `mix_hint`: ONE sentence about TIMING AND PLACEMENT ONLY. Max 14 words. \
          FIRST WORD MUST BE one of: Drop, Slot, Bridge, Open, Cut, Follow, Save, \
          Pair, Hold, Stack. Then say WHEN (specific hour or set position), what to \
          mix FROM, what to follow WITH. Reference the Stage 2 Timing label if \
          provided; otherwise infer the slot from BPM and Genre. \
          FORBIDDEN in `mix_hint` (these are sound-description words and belong in \
          `long`): vibe, atmosphere, feel, mood, dark, warm, deep, dreamy, soulful, \
          dirty, hypnotic, lush, raw, woozy, hazy, ethereal, gritty, drift, glow, \
          shimmer, pulse, thud, hum, cavernous, swirling, swung, walking, broken, \
          rolling — none of these describe DJ action.

        - Respond with the JSON object only. No leading prose. No code fences.
        """

        let user = """
        Track analysis:
        \(inputs.promptPayload())

        Write the three fields.
        """

        return (system, user)
    }

    /// Build the per-track forbidden-token list for `short`.
    ///
    /// Pulls every word from title, artist, genre, mood, vibes, style, instruments,
    /// rhythm, bassType, vocalType, and customTags, then strips punctuation, lowercases,
    /// drops common stop-words, drops single characters, and dedupes. The result is
    /// injected into the `short` rule so the model sees the literal tokens it must
    /// avoid for this specific track — much harder to ignore than abstract categories.
    internal static func forbiddenShortTokens(inputs: VibeGenerationInputs) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "of", "to", "in", "on", "at", "by",
            "for", "with", "is", "it", "as", "feat", "ft", "vs", "remix", "mix",
            "edit", "version", "original", "extended", "club", "radio",
            "instrumental", "vocal", "dub"
        ]
        var sources: [String] = []
        if let t = inputs.title { sources.append(t) }
        if let a = inputs.artist { sources.append(a) }
        let tags = inputs.predictedTags
        if let g = tags.genre { sources.append(g) }
        if let m = tags.mood { sources.append(m) }
        if let b = tags.bassType { sources.append(b) }
        if let v = tags.vocalType { sources.append(v) }
        sources.append(contentsOf: tags.vibes)
        sources.append(contentsOf: tags.style)
        sources.append(contentsOf: tags.instruments)
        sources.append(contentsOf: tags.rhythm)
        sources.append(contentsOf: tags.customTags)

        var seen: Set<String> = []
        var out: [String] = []
        for raw in sources {
            let cleaned = raw.unicodeScalars
                .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            let parts = String(cleaned).split(separator: " ")
            for part in parts {
                let token = part.lowercased()
                guard token.count >= 2, !stopWords.contains(token), seen.insert(token).inserted else { continue }
                out.append(token)
            }
        }
        return out
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
