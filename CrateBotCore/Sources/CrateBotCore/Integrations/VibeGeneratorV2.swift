import Foundation
import os.log

// MARK: - Errors

/// Errors that can occur during Stage 1–grounded vibe generation.
public enum VibeGeneratorError: Error, LocalizedError, Sendable {
    case apiKeyNotConfigured
    case parsingFailed(String)
    case validationFailed(String)
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Anthropic API key is not configured"
        case .parsingFailed(let detail):
            return "Failed to parse vibe response: \(detail)"
        case .validationFailed(let detail):
            return "Vibe response failed validation: \(detail)"
        case .generationFailed(let message):
            return "Vibe generation failed: \(message)"
        }
    }
}

// MARK: - Result

/// Strict three-output result of vibe generation.
///
/// - `short`: 5 word all-caps symbolic handle. TCOM target.
/// - `long`: Additive sensory/atmospheric description. TIT3 target.
/// - `mixHint`: DJ movement/placement guidance. MVNM target.
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

enum ShortSlot: String, CaseIterable, Sendable {
    case weight
    case density
    case texture
    case emotion
    case signature

    var index: Int {
        switch self {
        case .weight: return 0
        case .density: return 1
        case .texture: return 2
        case .emotion: return 3
        case .signature: return 4
        }
    }
}

public struct VibeBatchLedgerSnapshot: Sendable, Equatable {
    public let usedWordsBySlot: [String: [String: Int]]
    public let usedFamiliesBySlot: [String: [String: Int]]
    public let longTokens: [String: Int]

    public init(
        usedWordsBySlot: [String: [String: Int]] = [:],
        usedFamiliesBySlot: [String: [String: Int]] = [:],
        longTokens: [String: Int] = [:]
    ) {
        self.usedWordsBySlot = usedWordsBySlot
        self.usedFamiliesBySlot = usedFamiliesBySlot
        self.longTokens = longTokens
    }
}

/// Tracks words already committed in the current tagging batch.
///
/// The generator uses this as a soft diversity pressure: useful descriptors can
/// repeat when they are genuinely the best fit, but repeated slot words and
/// repeated semantic families become more expensive as the batch progresses.
public actor VibeBatchLedger {
    private var usedWordsBySlot: [String: [String: Int]] = [:]
    private var usedFamiliesBySlot: [String: [String: Int]] = [:]
    private var longTokens: [String: Int] = [:]

    public init() {}

    public func snapshot() -> VibeBatchLedgerSnapshot {
        VibeBatchLedgerSnapshot(
            usedWordsBySlot: usedWordsBySlot,
            usedFamiliesBySlot: usedFamiliesBySlot,
            longTokens: longTokens
        )
    }

    public func record(_ result: VibeGenerationResult) {
        let words = result.short.split(separator: " ").map { String($0).uppercased() }
        for (slot, word) in ShortSlot.allCases.prefix(words.count).map({ ($0, words[$0.index]) }) {
            usedWordsBySlot[slot.rawValue, default: [:]][word, default: 0] += 1
            let family = VibeGeneratorV2.family(for: word, in: slot)
            usedFamiliesBySlot[slot.rawValue, default: [:]][family, default: 0] += 1
        }

        for token in VibeGeneratorV2.significantTokens(in: result.long) {
            longTokens[token, default: 0] += 1
        }
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
    /// Bump whenever prompt semantics or validation rules change so stale cached
    /// generations cannot survive a behavior change.
    public static let cacheVersion = "vibe-generator-v4-slot-ledger-contrast-2026-06-14"

    private let client: VibeChatClient
    private let logger = Logger(subsystem: "com.cratebot", category: "VibeGeneratorV2")
    private static let maxGenerationAttempts = 2

    public init(client: VibeChatClient) {
        self.client = client
    }

    /// Generate a `VibeGenerationResult` from the given inputs.
    ///
    /// Short + long are generated and validated first. Movement (`mixHint`) is
    /// generated in a second pass that sees the completed fields, so its role is
    /// DJ placement/use rather than another description.
    public func generate(
        inputs: VibeGenerationInputs,
        batchLedger: VibeBatchLedger? = nil
    ) async throws -> VibeGenerationResult {
        let batchSnapshot = await batchLedger?.snapshot()
        var descriptionRepair: String?
        var resolvedDescription: (short: String, long: String)?
        var lastDescriptionError: Error?
        for _ in 0..<Self.maxGenerationAttempts {
            let (descriptionSystem, descriptionPrompt) = Self.composeDescriptionPrompts(
                inputs: inputs,
                batchSnapshot: batchSnapshot,
                repairHint: descriptionRepair
            )
            let descriptionRaw = try await complete(
                prompt: descriptionPrompt,
                system: descriptionSystem,
                maxTokens: 600
            )
            do {
                let description = try Self.decodeJSONObject(DescriptionWireResponse.self, from: descriptionRaw)
                let long = Self.normalizeSpaces(description.long)
                let short = try Self.selectShort(
                    from: description,
                    inputs: inputs,
                    long: long,
                    batchSnapshot: batchSnapshot
                )
                try Self.validateShort(short, inputs: inputs, long: long, batchSnapshot: batchSnapshot)
                try Self.validateLong(long, inputs: inputs, short: short, batchSnapshot: batchSnapshot)
                resolvedDescription = (short, long)
                break
            } catch let error as VibeGeneratorError {
                lastDescriptionError = error
                guard case .validationFailed(let detail) = error else { throw error }
                descriptionRepair = detail
            }
        }
        guard let resolvedDescription else {
            throw lastDescriptionError ?? VibeGeneratorError.generationFailed("description generation did not produce valid output")
        }
        let short = resolvedDescription.short
        let long = resolvedDescription.long

        var movementRepair: String?
        var resolvedMixHint: String?
        var lastMovementError: Error?
        for _ in 0..<Self.maxGenerationAttempts {
            let (movementSystem, movementPrompt) = Self.composeMovementPrompts(
                inputs: inputs,
                short: short,
                long: long,
                repairHint: movementRepair
            )
            let movementRaw = try await complete(
                prompt: movementPrompt,
                system: movementSystem,
                maxTokens: 300
            )
            do {
                let movement = try Self.decodeJSONObject(MovementWireResponse.self, from: movementRaw)
                let mixHint = Self.normalizeSpaces(movement.mix_hint)
                try Self.validateMovement(mixHint, inputs: inputs, short: short, long: long)
                resolvedMixHint = mixHint
                break
            } catch let error as VibeGeneratorError {
                lastMovementError = error
                guard case .validationFailed(let detail) = error else { throw error }
                movementRepair = detail
            }
        }
        guard let mixHint = resolvedMixHint else {
            throw lastMovementError ?? VibeGeneratorError.generationFailed("movement generation did not produce valid output")
        }

        let result = VibeGenerationResult(
            short: short,
            long: long,
            mixHint: mixHint
        )
        await batchLedger?.record(result)
        return result
    }

    private func complete(prompt: String, system: String, maxTokens: Int) async throws -> String {
        do {
            return try await client.complete(
                prompt: prompt,
                system: system,
                maxTokens: maxTokens,
                temperature: 0.7,
                model: AnthropicClient.defaultModel
            )
        } catch let error as AnthropicError {
            switch error {
            case .apiKeyNotConfigured:
                throw VibeGeneratorError.apiKeyNotConfigured
            case .requestFailed(let statusCode, let message)
                where statusCode == 401 && message.localizedCaseInsensitiveContains("x-api-key"):
                throw VibeGeneratorError.apiKeyNotConfigured
            default:
                throw VibeGeneratorError.generationFailed(error.localizedDescription)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VibeGeneratorError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Wire types

    // swiftlint:disable identifier_name
    private struct DescriptionWireResponse: Decodable {
        let weight_options: [String]
        let density_options: [String]
        let texture_options: [String]
        let emotion_options: [String]
        let signature_options: [String]
        let long: String

        func options(for slot: ShortSlot) -> [String] {
            switch slot {
            case .weight: return weight_options
            case .density: return density_options
            case .texture: return texture_options
            case .emotion: return emotion_options
            case .signature: return signature_options
            }
        }
    }

    private struct MovementWireResponse: Decodable {
        let mix_hint: String
    }
    // swiftlint:enable identifier_name

    private struct CompletedDescriptionsPayload: Encodable {
        let long: String
        let short: String
    }

    // MARK: - Prompt composition

    private static let curatedSlotVocabulary: [ShortSlot: [String]] = [
        .weight: [
            "HEAVY", "MASSIVE", "CHUNKY", "THICK", "SOLID", "WEIGHTY",
            "PUNCHY", "BEEFY", "LEAN", "LIGHT", "AIRY", "FLOATING",
            "WEIGHTLESS", "FEATHERY", "HOLLOW", "MUSCLED", "SLABBY",
            "SOFT", "HARD", "HUGE", "TINY", "DEEP", "LOW", "BRIGHT"
        ],
        .density: [
            "DENSE", "STACKED", "LAYERED", "BUSY", "FRANTIC", "CROWDED",
            "MAXIMAL", "TIGHT", "SPARSE", "STRIPPED", "MINIMAL", "OPEN",
            "ROOMY", "HOLLOW", "CLEAN", "PACKED", "ACTIVE", "RESTLESS",
            "PARED", "BROAD", "THIN", "THICK"
        ],
        .texture: [
            "RUBBERY", "GLASSY", "GRITTY", "DUSTY", "SILKY", "METALLIC",
            "SMOKY", "WET", "DRY", "FUZZY", "CHROME", "WOODEN",
            "PLASTIC", "VELVET", "RAW", "POLISHED", "CLIPPED", "JAGGED",
            "WARM", "COLD", "SANDY", "LIQUID", "CRISP", "DIRTY",
            "SWEATY", "GLOSSY"
        ],
        .emotion: [
            "JOYFUL", "SWEET", "SPICY", "NASTY", "TENDER", "ANGRY",
            "BRIGHT", "DARK", "WARM", "COOL", "SOUR", "PLAYFUL",
            "URGENT", "MELANCHOLY", "EUPHORIC", "FUNNY", "FLIRTY",
            "FIERCE", "SMUG", "LONELY", "HOPEFUL", "WEIRD", "SLY",
            "SUNNY", "BITTER", "ROMANTIC"
        ],
        .signature: [
            "ENGINE", "VEIL", "SUN", "WIRE", "SPARK", "SIREN", "DUST",
            "GLOW", "MIRROR", "FLAME", "HONEY", "STEEL", "SUGAR",
            "SMOKE", "RIBBON", "SWITCH", "SPRING", "NEEDLE", "HAMMER",
            "BALLOON", "LASER", "GARDEN", "FEVER", "THUNDER", "GLITTER",
            "SAND", "PEPPER", "SIGNAL", "MACHINE", "WINDOW", "ROPE",
            "TORCH", "COMET", "SHADOW"
        ]
    ]

    private static let curatedSlotSets: [ShortSlot: Set<String>] = {
        Dictionary(
            uniqueKeysWithValues: curatedSlotVocabulary.map { slot, words in
                (slot, Set(words))
            }
        )
    }()

    private static let slotFamilyMap: [ShortSlot: [String: String]] = [
        .weight: [
            "HEAVY": "heavy", "MASSIVE": "heavy", "CHUNKY": "heavy",
            "THICK": "heavy", "SOLID": "heavy", "WEIGHTY": "heavy",
            "PUNCHY": "heavy", "BEEFY": "heavy", "HARD": "heavy",
            "HUGE": "heavy", "DEEP": "heavy", "LOW": "heavy",
            "MUSCLED": "heavy", "SLABBY": "heavy",
            "LIGHT": "light", "AIRY": "light", "FLOATING": "light",
            "WEIGHTLESS": "light", "FEATHERY": "light", "SOFT": "light",
            "TINY": "light", "BRIGHT": "light",
            "LEAN": "lean", "HOLLOW": "lean"
        ],
        .density: [
            "DENSE": "full", "STACKED": "full", "LAYERED": "full",
            "CROWDED": "full", "MAXIMAL": "full", "PACKED": "full",
            "THICK": "full",
            "BUSY": "active", "FRANTIC": "active", "ACTIVE": "active",
            "RESTLESS": "active",
            "SPARSE": "open", "STRIPPED": "open", "MINIMAL": "open",
            "OPEN": "open", "ROOMY": "open", "HOLLOW": "open",
            "CLEAN": "open", "PARED": "open", "BROAD": "open",
            "THIN": "open",
            "TIGHT": "tight"
        ],
        .texture: [
            "RUBBERY": "elastic", "PLASTIC": "elastic",
            "LIQUID": "elastic", "WET": "elastic",
            "GLASSY": "shiny", "CHROME": "shiny", "METALLIC": "shiny",
            "POLISHED": "shiny", "GLOSSY": "shiny",
            "GRITTY": "rough", "DUSTY": "rough", "RAW": "rough",
            "SANDY": "rough", "DIRTY": "rough", "SWEATY": "rough",
            "FUZZY": "rough",
            "SILKY": "soft", "VELVET": "soft", "SMOKY": "soft",
            "CLIPPED": "sharp", "JAGGED": "sharp", "CRISP": "sharp",
            "DRY": "sharp",
            "WARM": "temperature", "COLD": "temperature", "WOODEN": "organic"
        ],
        .emotion: [
            "JOYFUL": "joy", "PLAYFUL": "joy", "SUNNY": "joy",
            "EUPHORIC": "joy", "FUNNY": "joy",
            "SWEET": "warm", "TENDER": "warm", "ROMANTIC": "warm",
            "HOPEFUL": "warm", "WARM": "warm", "BRIGHT": "warm",
            "SPICY": "spice", "NASTY": "spice", "FLIRTY": "spice",
            "SLY": "spice", "SMUG": "spice",
            "ANGRY": "charge", "FIERCE": "charge", "URGENT": "charge",
            "DARK": "shadow", "MELANCHOLY": "shadow", "LONELY": "shadow",
            "BITTER": "shadow", "SOUR": "shadow", "COOL": "shadow",
            "WEIRD": "shadow"
        ],
        .signature: [
            "SUN": "light", "SPARK": "light", "GLOW": "light",
            "FLAME": "light", "GLITTER": "light", "TORCH": "light",
            "ENGINE": "machine", "WIRE": "machine", "SWITCH": "machine",
            "NEEDLE": "machine", "LASER": "machine", "SIGNAL": "machine",
            "MACHINE": "machine",
            "MIRROR": "material", "STEEL": "material", "RIBBON": "material",
            "VEIL": "material", "ROPE": "material", "WINDOW": "material",
            "DUST": "air", "SMOKE": "air", "SAND": "air",
            "SHADOW": "air", "COMET": "air",
            "THUNDER": "force", "HAMMER": "force", "SIREN": "force",
            "HONEY": "flavor", "SUGAR": "flavor", "PEPPER": "flavor",
            "FEVER": "flavor",
            "BALLOON": "play", "GARDEN": "place", "SPRING": "spring"
        ]
    ]

    internal static func family(for word: String, in slot: ShortSlot) -> String {
        let normalized = normalizeOptionWord(word) ?? word.uppercased()
        return slotFamilyMap[slot]?[normalized] ?? normalized.lowercased()
    }

    private static func slotVocabularyPrompt() -> String {
        ShortSlot.allCases.map { slot in
            let words = curatedSlotVocabulary[slot, default: []].joined(separator: ", ")
            return "- \(slot.rawValue)_options: \(words)"
        }
        .joined(separator: "\n")
    }

    private static func renderCounts(_ counts: [String: Int], limit: Int = 12) -> String {
        let rendered = counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map { "\($0.key)(\($0.value))" }
            .joined(separator: ", ")
        return rendered.isEmpty ? "none" : rendered
    }

    private static func batchDiversityPrompt(_ snapshot: VibeBatchLedgerSnapshot?) -> String {
        guard let snapshot else {
            return "Current batch history: none yet."
        }

        let usedSlotWords = ShortSlot.allCases.map { slot -> String in
            let counts = snapshot.usedWordsBySlot[slot.rawValue, default: [:]]
            return "\(slot.rawValue): \(renderCounts(counts, limit: 8))"
        }
        .joined(separator: "; ")
        let usedSlotFamilies = ShortSlot.allCases.map { slot -> String in
            let counts = snapshot.usedFamiliesBySlot[slot.rawValue, default: [:]]
            return "\(slot.rawValue): \(renderCounts(counts, limit: 8))"
        }
        .joined(separator: "; ")
        let longTokens = renderCounts(snapshot.longTokens, limit: 16)

        return """
        Current batch diversity pressure:
        - Used slot words: \(usedSlotWords)
        - Used slot families: \(usedSlotFamilies)
        - Already-used long-image tokens: \(longTokens)
        Prefer unused words, unused semantic families, and fresh sensory images unless the audio evidence strongly demands a repeat.
        """
    }

    /// Compose the first-pass prompt for `short` + `long`.
    ///
    /// The movement hint is deliberately omitted here. It is generated in a
    /// second pass after these two fields exist.
    internal static func composeDescriptionPrompts(
        inputs: VibeGenerationInputs,
        batchSnapshot: VibeBatchLedgerSnapshot? = nil,
        repairHint: String? = nil
    ) -> (system: String, user: String) {
        let forbidden = Self.forbiddenSourceTokens(inputs: inputs)
        let forbiddenLine = forbidden.isEmpty
            ? ""
            : " FORBIDDEN source words for THIS track: \(forbidden.joined(separator: ", "))."
        let batchLine = Self.batchDiversityPrompt(batchSnapshot)
        let repairBlock = repairHint.map {
            """

            Previous response failed validation:
            \($0)

            Return corrected JSON only.
            """
        } ?? ""

        let system = """
        You are a veteran DJ tagging a record crate. Given a JSON analysis of one \
        electronic music track, respond with JSON only — no prose, no markdown fences, \
        no preamble.

        Write candidate words for a deterministic Composer selector plus one long \
        description. Do not write the final Composer string yourself.

          • `weight_options` — physical mass/heaviness of the track: heavy, light, \
            floating, chunky, huge, lean, etc.

          • `density_options` — busyness/layering/sparseness: frantic, packed, \
            stripped, open, active, minimal, etc.

          • `texture_options` — sonic surface/material: rubbery, glassy, gritty, \
            silky, chrome, dusty, etc.

          • `emotion_options` — taste/color/sentiment: joyful, spicy, tender, sour, \
            fierce, lonely, etc.

          • `signature_options` — one concrete symbolic image that makes THIS track \
            memorable without repeating the tags.

          • `long` — additive sensory atmosphere. It describes the feeling, scene, \
            energy, texture, weather, pressure, color, smell, taste, and moment the \
            track creates. It must NOT restate the artist, album, title, genre, mood, \
            timing, instruments, style, rhythm, vocal/bass labels, custom tags, or \
            any candidate option word. It must NOT say how a DJ should play it.

        Output schema:
        {"weight_options":["<WORD>"],"density_options":["<WORD>"],"texture_options":["<WORD>"],"emotion_options":["<WORD>"],"signature_options":["<WORD>"],"long":"<one compact evocative description>"}

        Composer selector vocabulary:
        \(slotVocabularyPrompt())

        \(batchLine)

        Hard rules:
        - Each *_options array: 3 to 6 candidate words, each one word, ALL CAPS, \
          no punctuation, no numbers, no articles. Use the vocabulary above for \
          weight/density/texture/emotion unless the audio strongly needs a better \
          word. Signature can be more image-led, but keep it short and concrete. \
          Do not use any source word or `long` word.\(forbiddenLine)
        - `long`: 6 to 32 words. Evocative and sensory, not a tag summary, not a \
          music-review inventory, and not DJ instructions. Do not start with \
          "This", "A", "An", or "The"; do not use "track", "song", or "tune". \
          Avoid repeated sentence formulas such as "X while Y creating Z". Do not \
          use any source word or candidate option word.\(forbiddenLine)
        - Respond with the JSON object only. No leading prose. No code fences.
        """

        let user = """
        Track analysis:
        \(inputs.promptPayload())

        Write slot candidate arrays and `long`.\(repairBlock)
        """

        return (system, user)
    }

    /// Compose the second-pass prompt for movement/mix placement.
    internal static func composeMovementPrompts(
        inputs: VibeGenerationInputs,
        short: String,
        long: String,
        repairHint: String? = nil
    ) -> (system: String, user: String) {
        let forbidden = Self.forbiddenSourceTokens(inputs: inputs)
        let completed = Self.completedDescriptionsPayload(short: short, long: long)
        let forbiddenLine = forbidden.isEmpty
            ? ""
            : " Also avoid these source words: \(forbidden.joined(separator: ", "))."
        let repairBlock = repairHint.map {
            """

            Previous response failed validation:
            \($0)

            Return corrected JSON only.
            """
        } ?? ""

        let system = """
        You are writing the Movement Name / DJ-use field for one electronic track. \
        Respond with JSON only — no prose, no markdown fences, no preamble.

        The `short` and `long` fields are already written. Read them, then write \
        `mix_hint` as a different kind of information: how a DJ should use the track \
        relative to other records and moments.

        `mix_hint` is short-form DJ placement language: timing, slot, transition job, \
        what to put it after, what it can set up, what kind of energy shift it creates. \
        Good shapes include: "2AM pressure lift after rough drums", "Bridge from \
        dirty drop into brighter lift", "Save for toughness after a beautiful reset".

        It must NOT describe the track's vibe, atmosphere, scene, sound, instruments, \
        texture, or sensory image. It must NOT reuse meaningful words from `short` or \
        `long`.\(forbiddenLine)

        Output schema:
        {"mix_hint": "<short DJ-use phrase>"}

        Hard rules:
        - `mix_hint`: 4 to 22 words. Fragment is fine. No "this is", "this track", \
          "as a DJ", filler, explanation, or review prose.
        - Say when/how to use it: a time, set position, transition role, what to come \
          after, what to move into, or what energy job it performs.
        - Do not simply repeat Timing, Genre, Mood, or descriptive tags. Translate \
          those into a useful DJ action.
        - Respond with the JSON object only.
        """

        let user = """
        Track analysis:
        \(inputs.promptPayload())

        Completed fields:
        \(completed)

        Write `mix_hint`.\(repairBlock)
        """

        return (system, user)
    }

    /// Build the per-track forbidden-token list used by prompts and validators.
    ///
    /// Pulls words from metadata and every predicted tag category, including album
    /// and timing, so generated prose has to add information instead of restating
    /// the existing tag stack.
    internal static func forbiddenSourceTokens(inputs: VibeGenerationInputs) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "of", "to", "in", "on", "at", "by",
            "for", "with", "is", "it", "as", "feat", "ft", "vs"
        ]
        var sources: [String] = []
        if let title = inputs.title { sources.append(title) }
        if let artist = inputs.artist { sources.append(artist) }
        if let album = inputs.album { sources.append(album) }
        let tags = inputs.predictedTags
        if let genre = tags.genre { sources.append(genre) }
        if let timing = tags.timing { sources.append(timing) }
        if let mood = tags.mood { sources.append(mood) }
        if let bassType = tags.bassType { sources.append(bassType) }
        if let vocalType = tags.vocalType { sources.append(vocalType) }
        if tags.acapella == true { sources.append("Acapella") }
        sources.append(contentsOf: tags.vibes)
        sources.append(contentsOf: tags.style)
        sources.append(contentsOf: tags.instruments)
        sources.append(contentsOf: tags.rhythm)
        sources.append(contentsOf: tags.customTags)

        var seen: Set<String> = []
        var out: [String] = []
        for raw in sources {
            for token in lexicalTokens(in: raw) {
                guard token.count >= 2, !stopWords.contains(token), seen.insert(token).inserted else { continue }
                out.append(token)
            }
        }
        return out
    }

    private static func completedDescriptionsPayload(short: String, long: String) -> String {
        let payload = CompletedDescriptionsPayload(long: long, short: short)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    // MARK: - Short selection

    private static let shortAllowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private static func selectShort(
        from description: DescriptionWireResponse,
        inputs: VibeGenerationInputs,
        long: String,
        batchSnapshot: VibeBatchLedgerSnapshot?
    ) throws -> String {
        let forbidden = Set(forbiddenSourceTokens(inputs: inputs))
        let longTokens = significantTokens(in: long)
        var selected: [String] = []

        for slot in ShortSlot.allCases {
            let word = try selectWord(
                for: slot,
                rawOptions: description.options(for: slot),
                forbidden: forbidden,
                longTokens: longTokens,
                selected: selected,
                batchSnapshot: batchSnapshot
            )
            selected.append(word)
        }

        return selected.joined(separator: " ")
    }

    private static func selectWord(
        for slot: ShortSlot,
        rawOptions: [String],
        forbidden: Set<String>,
        longTokens: Set<String>,
        selected: [String],
        batchSnapshot: VibeBatchLedgerSnapshot?
    ) throws -> String {
        let curated = curatedSlotSets[slot, default: []]
        let usedWords = batchSnapshot?.usedWordsBySlot[slot.rawValue] ?? [:]
        let usedFamilies = batchSnapshot?.usedFamiliesBySlot[slot.rawValue] ?? [:]
        let batchLongTokens = batchSnapshot?.longTokens ?? [:]
        let alreadySelected = Set(selected)
        var seen: Set<String> = []
        var best: (word: String, score: Double, index: Int)?

        for (index, raw) in rawOptions.enumerated() {
            guard let word = normalizeOptionWord(raw), seen.insert(word).inserted else {
                continue
            }
            let lower = word.lowercased()
            guard !forbidden.contains(lower),
                  !longTokens.contains(lower),
                  !alreadySelected.contains(word) else {
                continue
            }

            let family = family(for: word, in: slot)
            var score = 0.0
            if curated.contains(word) {
                score += 6
            } else if slot == .signature {
                score += 2
            } else {
                score -= 3
            }
            score += Double(max(0, 12 - word.count)) * 0.05
            score -= Double(index) * 0.2
            score -= Double(usedWords[word] ?? 0) * 12
            score -= Double(usedFamilies[family] ?? 0) * 5
            score -= Double(batchLongTokens[lower] ?? 0) * 3
            if slot == .signature {
                score -= Double(usedWords[word] ?? 0) * 8
            }

            if let current = best {
                if score > current.score
                    || (score == current.score && index < current.index)
                    || (score == current.score && index == current.index && word < current.word) {
                    best = (word, score, index)
                }
            } else {
                best = (word, score, index)
            }
        }

        guard let best else {
            throw VibeGeneratorError.validationFailed("\(slot.rawValue)_options has no usable word candidates; avoid source words, repeated slot words, and long-description words")
        }
        return best.word
    }

    private static func normalizeOptionWord(_ raw: String) -> String? {
        let normalized = normalizeSpaces(raw)
        let parts = normalized.split(separator: " ").map(String.init)
        guard parts.count == 1 else { return nil }
        let word = parts[0].uppercased()
        guard (3...12).contains(word.count),
              !articles.contains(word.lowercased()) else {
            return nil
        }
        for scalar in word.unicodeScalars {
            guard shortAllowedCharacters.contains(scalar) else { return nil }
        }
        return word
    }

    // MARK: - Validation

    private static let articles: Set<String> = ["a", "an", "the"]

    private static let semanticStopWords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "in", "on", "at", "by",
        "for", "with", "from", "into", "after", "before", "between", "when",
        "then", "than", "that", "this", "these", "those", "is", "are", "was",
        "were", "be", "been", "being", "it", "its", "as", "but", "not", "no",
        "so", "if", "you", "your", "their", "there", "here", "over", "under",
        "through", "across", "against", "inside", "outside", "near", "toward",
        "track", "field", "music", "record"
    ]

    private static let longInstructionTokens: Set<String> = [
        "dj", "mix", "drop", "play", "set", "slot", "opener", "closer",
        "warmup", "warm-up", "transition", "segue", "blend", "cue", "follow",
        "prime", "peak-time"
    ]

    private static let longBannedLeadingTokens: Set<String> = [
        "this", "that", "these", "those", "a", "an", "the"
    ]

    private static let longBannedReviewTokens: Set<String> = [
        "track", "song", "tune"
    ]

    private static let longBannedFormulaTokens: Set<String> = [
        "creating", "featuring"
    ]

    private static let movementCueTokens: Set<String> = [
        "drop", "slot", "bridge", "open", "cut", "follow", "save", "pair",
        "hold", "stack", "after", "before", "between", "from", "into", "when",
        "build", "lift", "shift", "release", "reset", "transition", "segue",
        "opener", "closer", "warmup", "warm-up", "energy", "toughness",
        "pressure", "drums", "break", "breakdown"
    ]

    internal static func validateShort(
        _ short: String,
        inputs: VibeGenerationInputs,
        long: String,
        batchSnapshot: VibeBatchLedgerSnapshot? = nil
    ) throws {
        guard !short.isEmpty else {
            throw VibeGeneratorError.validationFailed("short is empty")
        }
        let words = short.split(separator: " ").map(String.init)
        guard words.count == ShortSlot.allCases.count else {
            throw VibeGeneratorError.validationFailed("short must be 5 slot words: \(short)")
        }
        guard short == short.uppercased() else {
            throw VibeGeneratorError.validationFailed("short must be all caps: \(short)")
        }
        for scalar in short.unicodeScalars {
            if scalar == " " { continue }
            guard CharacterSet.uppercaseLetters.contains(scalar) else {
                throw VibeGeneratorError.validationFailed("short contains punctuation, numbers, or non-capitals: \(short)")
            }
        }
        for word in words {
            let lower = word.lowercased()
            if articles.contains(lower) {
                throw VibeGeneratorError.validationFailed("short contains article '\(word)'")
            }
            if word.count > 12 {
                throw VibeGeneratorError.validationFailed("short word is too long: \(word)")
            }
        }

        try rejectSourceRepeats(in: short, inputs: inputs, field: "short")
        let overlap = significantTokens(in: short).intersection(significantTokens(in: long))
        if let token = overlap.sorted().first {
            throw VibeGeneratorError.validationFailed("short repeats long token '\(token)'")
        }
    }

    internal static func validateLong(
        _ long: String,
        inputs: VibeGenerationInputs,
        short: String,
        batchSnapshot: VibeBatchLedgerSnapshot? = nil
    ) throws {
        guard !long.isEmpty else {
            throw VibeGeneratorError.validationFailed("long is empty")
        }
        let words = lexicalTokens(in: long)
        guard (6...32).contains(words.count) else {
            throw VibeGeneratorError.validationFailed("long must be 6 to 32 words: \(long)")
        }
        let lower = long.lowercased()
        let badPrefixes = ["this is", "it is", "it's"]
        if badPrefixes.contains(where: { lower.hasPrefix($0) }) {
            throw VibeGeneratorError.validationFailed("long uses summary/prose filler: \(long)")
        }
        if let first = words.first, longBannedLeadingTokens.contains(first) {
            throw VibeGeneratorError.validationFailed("long starts with banned article/demonstrative '\(first)'")
        }
        let reviewOverlap = Set(words).intersection(longBannedReviewTokens)
        if let token = reviewOverlap.sorted().first {
            throw VibeGeneratorError.validationFailed("long uses generic review noun '\(token)'")
        }
        let formulaOverlap = Set(words).intersection(longBannedFormulaTokens)
        if let token = formulaOverlap.sorted().first {
            throw VibeGeneratorError.validationFailed("long uses stale formula token '\(token)'")
        }
        let instructionOverlap = Set(words).intersection(longInstructionTokens)
        if let token = instructionOverlap.sorted().first {
            throw VibeGeneratorError.validationFailed("long contains DJ-use token '\(token)'")
        }

        try rejectSourceRepeats(in: long, inputs: inputs, field: "long")
        let overlap = significantTokens(in: long).intersection(significantTokens(in: short))
        if let token = overlap.sorted().first {
            throw VibeGeneratorError.validationFailed("long repeats short token '\(token)'")
        }
        if let batchSnapshot {
            let repeated = significantTokens(in: long)
                .filter { (batchSnapshot.longTokens[$0] ?? 0) > 0 }
                .sorted()
            if repeated.count >= 2 {
                throw VibeGeneratorError.validationFailed("long repeats batch image tokens \(repeated.prefix(4).joined(separator: ", "))")
            }
        }
    }

    internal static func validateMovement(
        _ movement: String,
        inputs: VibeGenerationInputs,
        short: String,
        long: String
    ) throws {
        guard !movement.isEmpty else {
            throw VibeGeneratorError.validationFailed("mix_hint is empty")
        }
        let words = lexicalTokens(in: movement)
        guard (4...22).contains(words.count) else {
            throw VibeGeneratorError.validationFailed("mix_hint must be 4 to 22 words: \(movement)")
        }
        let lower = movement.lowercased()
        let fillerPhrases = ["this track", "this is", "it is", "it's", "as a dj", "you know", " ah "]
        if fillerPhrases.contains(where: { lower.contains($0) || lower.hasPrefix($0.trimmingCharacters(in: .whitespaces)) }) {
            throw VibeGeneratorError.validationFailed("mix_hint uses filler/prose phrasing: \(movement)")
        }

        let cueOverlap = Set(words).intersection(movementCueTokens)
        let hasClockTime = lower.range(
            of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#,
            options: .regularExpression
        ) != nil
        guard !cueOverlap.isEmpty || hasClockTime else {
            throw VibeGeneratorError.validationFailed("mix_hint lacks DJ timing/placement cue: \(movement)")
        }

        try rejectSourceRepeats(in: movement, inputs: inputs, field: "mix_hint")
        let completedTokens = significantTokens(in: short).union(significantTokens(in: long))
        let overlap = significantTokens(in: movement).intersection(completedTokens)
        if let token = overlap.sorted().first {
            throw VibeGeneratorError.validationFailed("mix_hint repeats completed description token '\(token)'")
        }
    }

    private static func rejectSourceRepeats(
        in text: String,
        inputs: VibeGenerationInputs,
        field: String
    ) throws {
        let forbidden = Set(forbiddenSourceTokens(inputs: inputs))
        let overlap = significantTokens(in: text).intersection(forbidden)
        if let token = overlap.sorted().first {
            throw VibeGeneratorError.validationFailed("\(field) repeats source/tag token '\(token)'")
        }
    }

    internal static func normalizeSpaces(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    internal static func lexicalTokens(in text: String) -> [String] {
        let cleaned = text.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned)
            .split(separator: " ")
            .map { $0.lowercased() }
    }

    internal static func significantTokens(in text: String) -> Set<String> {
        Set(lexicalTokens(in: text).filter { $0.count >= 3 && !semanticStopWords.contains($0) })
    }

    // MARK: - Parsing helpers

    private static func decodeJSONObject<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let stripped = Self.stripFences(raw)
        let extracted = Self.extractFirstJSONObject(from: stripped)
        guard let json = extracted,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(type, from: data) else {
            let snippet = String((extracted ?? raw).prefix(500))
            throw VibeGeneratorError.parsingFailed(snippet)
        }
        return decoded
    }

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
