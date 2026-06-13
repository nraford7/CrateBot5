# Vibe Generator v2 Implementation Plan

> **For Claude:** REQUIRED: Execute via Agency. Chunk-boundary two-stage review. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the unwired legacy `NativeVibeGenerator` with `VibeGeneratorV2` — Stage 1–grounded, three-output (TCOM/TIT3/TXXX:CRATEBOT_MIXHINT), opt-in toggle in Tagging Options. Per spec `2026-06-13-vibe-generator-v2-design.md`.

**Tech Stack:** Swift / SwiftPM, Anthropic Sonnet 4, XCTest. Baseline 459/0.

---

## Chunk 1: TaggingResult exposes Stage 2 Timing prediction

### Task 1.1: TimingPrediction surfaced on TaggingResult

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` (TaggingResult ~L24-57, judgmentPass ~L777-792, analyze return path)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` UserTagPredictions if needed (it isn't — keep timing as String?, add a parallel field on TaggingResult)
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineTests.swift`

- [ ] **Step 1: Failing test** asserting that after analyze, `TaggingResult.timingPrediction` carries label + calibrated confidence when a judgment classifier triggered, and is nil when judgmentAvailable is false:

```swift
func testTimingPredictionSurfacedWhenJudgmentFires() async throws {
    // Use the same paired-model fixture as testJudgmentInferenceFiresForPairedModels
    // Assert result.timingPrediction?.label == "Peak"
    // Assert result.timingPrediction!.confidence > 0.5
}

func testTimingPredictionNilWhenJudgmentUnavailable() async throws {
    // Engine loaded without judgment models
    // Assert result.judgmentAvailable == false
    // Assert result.timingPrediction == nil
}
```

- [ ] **Step 2: Run, verify FAIL** — `cd CrateBotCore && swift test --filter TaggingEngineTests`

- [ ] **Step 3: Implement.** Add `TimingPrediction` struct and field on `TaggingResult`:

```swift
public struct TimingPrediction: Sendable, Equatable {
    public let label: String
    public let confidence: Float
    public init(label: String, confidence: Float) { self.label = label; self.confidence = confidence }
}

// TaggingResult adds:
public let timingPrediction: TimingPrediction?
// init gains: timingPrediction: TimingPrediction? = nil
```

`judgmentPass` already computes per-classifier confidences before applying `effectiveThreshold` — capture the argmax label + confidence and return it alongside `judgmentAvailable`. Wire it through to the result construction at the end of `analyze`. **Backwards-compatible:** the new init parameter has a default of `nil`, so existing test fixtures compile unchanged.

- [ ] **Step 4: Run, PASS, full suite (target 461/0).**

- [ ] **Step 5: Commit** — `feat: TaggingResult exposes Stage 2 timing prediction with confidence` + Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>.

**CHUNK 1 REVIEW GATE** (two-stage: requesting-code-review + independent no-context subagent).

---

## Chunk 2: VibeGenerationInputs + CooccurrenceContext extractor

### Task 2.1: CooccurrenceContext + extractor

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Integrations/CooccurrenceContext.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/CooccurrenceContextTests.swift`

**Important data fact (verified):** `tag_cooccurrence.json` schema is `{base_rates, conditional, total_tracks, version}` — symmetric pairwise P(other | tag). At time of writing, `conditional["Peak"] = {}` because the original co-occurrence stats were generated *before* the field-mapping fix landed and Timing tags trained on near-empty data. **After Noah's next retrain + regeneration of co-occurrence stats**, those entries populate. The extractor must work both before and after — it returns nil when support is thin, never throws or invents.

- [ ] **Step 1: Failing tests:**

```swift
func testCooccurrenceContextReturnsTopKAboveBaseRate() {
    // Synthetic stats: base_rates House=0.5, conditional["Peak"]={"House":0.9,"Dark":0.6,"Acapella":0.05}, total_tracks=100
    // Context for timing="Peak" topK=2 → ["House", "Dark"] (Acapella excluded: below or near base rate)
}

func testCooccurrenceContextNilWhenSupportThin() {
    // total_tracks=1 → nil
    // or conditional["Peak"]={} → nil
}

func testCooccurrenceContextExcludesTrivialFrequencyArtifacts() {
    // Tag with high P(other|timing) but ALSO high base_rate → excluded
    // The lift must be >= configured threshold (default 1.2x base rate)
}
```

- [ ] **Step 2: Implement** as a value type with a static loader from the bundle resource and a pure function for the lift computation:

```swift
public struct CooccurrenceContext: Sendable, Equatable {
    public let timingLabel: String
    public let coOccurringTags: [String]   // ordered, top-K
    public let support: Int                // total_tracks contributing
}

public enum Cooccurrence {
    public struct Stats: Decodable, Sendable {
        public let base_rates: [String: Double]
        public let conditional: [String: [String: Double]]
        public let total_tracks: Int
    }
    public static func loadFromBundle() -> Stats? { /* JSON Data load */ }
    public static func context(
        forTags: Set<String>,                       // currently unused for v1; kept in signature for future
        timing: String,
        stats: Stats,
        topK: Int = 3,
        minSupport: Int = 3,
        minLift: Double = 1.2
    ) -> CooccurrenceContext? {
        guard stats.total_tracks >= minSupport else { return nil }
        guard let row = stats.conditional[timing], !row.isEmpty else { return nil }
        let scored = row.compactMap { (tag, p) -> (String, Double)? in
            let base = stats.base_rates[tag] ?? 0
            guard base > 0 else { return nil }
            let lift = p / base
            return lift >= minLift ? (tag, lift) : nil
        }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(topK).map { $0.0 }
        guard !top.isEmpty else { return nil }
        return CooccurrenceContext(timingLabel: timing, coOccurringTags: Array(top), support: stats.total_tracks)
    }
}
```

- [ ] **Step 3: Run, PASS, commit** — `feat: CooccurrenceContext extracts lift-ranked co-occurring tags for a timing label`.

### Task 2.2: VibeGenerationInputs value type

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Integrations/VibeGenerationInputs.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/VibeGenerationInputsTests.swift`

- [ ] **Step 1: Failing test** asserting the type round-trips its fields and produces a deterministic prompt-ready dictionary representation (column order is part of the schema — same logic as `JudgmentFeatureVector`).
- [ ] **Step 2: Implement** as a struct with all fields the spec lists. Add `promptPayload() -> String` that produces a JSON-formatted string of the inputs (sorted keys, fixed numeric precision) suitable for inclusion in the user prompt. This is the **single source of truth** for what the LLM sees — prompt template doesn't reach in and re-format fields ad hoc.
- [ ] **Step 3: PASS, commit** — `feat: VibeGenerationInputs schema for the generator prompt`.

**CHUNK 2 REVIEW GATE.**

---

## Chunk 3: VibeGeneratorV2 actor with strict JSON parsing

### Task 3.1: VibeGeneratorV2 implementation + tests

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Integrations/VibeGeneratorV2.swift`
- Rename: `CrateBotCore/Sources/CrateBotCore/Integrations/NativeVibeGenerator.swift` → keep as `NativeVibeGenerator+Deprecated.swift` with `@available(*, deprecated, message: "Use VibeGeneratorV2")` — one-version shim, do not delete now (the test suite may reference it).
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/VibeGeneratorV2Tests.swift`

- [ ] **Step 1: Failing tests** (mock `AnthropicClient` via a protocol — extract `protocol VibeChatClient` from the existing `AnthropicClient.complete` surface so tests don't hit the network):

```swift
func testValidJSONResponseProducesAllThreeFields() async throws {
    let mock = MockClient(reply: #"{"short":"Late Night Groove","long":"sustained, low-lit","mix_hint":"sits between Peak and Release"}"#)
    let gen = VibeGeneratorV2(client: mock)
    let r = try await gen.generate(inputs: sampleInputsWithMixHintAllowed)
    XCTAssertEqual(r.short, "Late Night Groove")
    XCTAssertEqual(r.long, "sustained, low-lit")
    XCTAssertEqual(r.mixHint, "sits between Peak and Release")
}

func testChainOfThoughtPreambleIsRejected() async throws {
    let mock = MockClient(reply: "LOOKING AT THIS TRACK ANALYSIS: this is peak\nVIBE: Peak Roller")
    let gen = VibeGeneratorV2(client: mock)
    await XCTAssertThrowsErrorAsync(try await gen.generate(inputs: sampleInputs))
    // Specifically: VibeGeneratorError.parsingFailed
}

func testMixHintOmittedWhenInputsHaveNoCooccurrence() async throws {
    // Inputs.cooccurrence == nil
    // Mock returns {"short":"X","long":"Y"} (no mix_hint key)
    // Expect r.mixHint == nil, no throw
}

func testMixHintGateBelowStage2Confidence() async throws {
    // Inputs.stage2Timing.confidence == 0.4 → generator strips cooccurrence/mix-hint from prompt and accepts a no-mix-hint response
}

func testTemperatureAndModelMatchSpec() async {
    let mock = SpyClient()
    let gen = VibeGeneratorV2(client: mock)
    _ = try? await gen.generate(inputs: sampleInputs)
    XCTAssertEqual(mock.lastTemperature, 0.7, accuracy: 0.001)
    XCTAssertEqual(mock.lastModel, AnthropicClient.defaultModel)
}
```

- [ ] **Step 2: Implement** the actor:

```swift
public enum VibeGeneratorError: Error, LocalizedError, Sendable {
    case apiKeyNotConfigured
    case parsingFailed(String)
    case generationFailed(String)
}

public struct VibeGenerationResult: Sendable, Equatable {
    public let short: String
    public let long: String
    public let mixHint: String?
}

public protocol VibeChatClient: Sendable {
    func complete(prompt: String, system: String, maxTokens: Int, temperature: Double, model: String) async throws -> String
}

public actor VibeGeneratorV2 {
    private let client: VibeChatClient
    public init(client: VibeChatClient) { self.client = client }

    public func generate(inputs: VibeGenerationInputs) async throws -> VibeGenerationResult {
        let mixHintAllowed = (inputs.stage2Timing?.confidence ?? 0) > 0.5 && inputs.cooccurrence != nil
        let (system, prompt) = Self.composePrompts(inputs: inputs, includeMixHint: mixHintAllowed)
        let raw = try await client.complete(
            prompt: prompt,
            system: system,
            maxTokens: 600,
            temperature: 0.7,
            model: AnthropicClient.defaultModel
        )
        // Strict JSON parse, no fallback to raw text. Strip leading code fences if present.
        let trimmed = Self.stripFences(raw)
        guard let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WireResponse.self, from: data),
              !decoded.short.isEmpty, !decoded.long.isEmpty else {
            throw VibeGeneratorError.parsingFailed(String(trimmed.prefix(500)))
        }
        return VibeGenerationResult(
            short: decoded.short, long: decoded.long,
            mixHint: mixHintAllowed ? decoded.mix_hint : nil
        )
    }

    private struct WireResponse: Decodable { let short: String; let long: String; let mix_hint: String? }
    // composePrompts: system tells model to output strict JSON, no preamble, no markdown.
    // user prompt embeds inputs.promptPayload() and a brief "describe the track's feel" instruction.
}
```

The existing `AnthropicClient.complete(prompt:system:maxTokens:)` doesn't accept temperature/model parameters today — add them with sensible defaults so existing callers (other tests) compile unchanged, OR wrap the existing call in a small adapter that conforms to `VibeChatClient`. Pick the smaller surface change after reading the existing signature; document the choice.

- [ ] **Step 3: PASS, commit** — `feat: VibeGeneratorV2 strict-JSON Stage1-grounded vibe + description + mix hint`.

**CHUNK 3 REVIEW GATE.**

---

## Chunk 4: Tagging pipeline integration + Settings UI + cache

### Task 4.1: TaggingPreferences.aiDescriptions field

**Files:**
- Modify: `CrateBot/App/AppState.swift` (TaggingPreferences ~L467, init(from:) ~L505-516, encode(to:) ~L530-540)
- Test: `CrateBotCore/Tests/CrateBotCoreTests/` — write a tiny round-trip test for the Codable migration even though TaggingPreferences lives in the app target (the type can be made internal-testable via a copy or refactored into Core later; for now do a pragmatic check inside an app `#if DEBUG` helper invoked by the assigned agent and pasted as evidence). If app gains a test target later, the formal XCTest goes there.

- [ ] **Step 1: Implement** `aiDescriptions: FieldPreference(enabled: false, targetField: "TCOM")` with the manual `decodeIfPresent` + explicit `encode` lines per spec.
- [ ] **Step 2: Verify** the legacy migration path still works — pre-existing saved JSON without the new key decodes correctly with the field defaulting to disabled. Demonstrate via a small inline JSON round-trip the agent runs.
- [ ] **Step 3: Commit** — `feat: TaggingPreferences.aiDescriptions opt-in toggle`.

### Task 4.2: Tagging pipeline integration

**Files:**
- Modify: `CrateBot/Views/TaggingView.swift` (~L770-810, the per-track tag-write loop)
- Modify: `CrateBotCore/Sources/CrateBotCore/Tags/TagMapping.swift` (already has vibeShort/vibeDescription; **add `mixHint: String?` to the relevant tag types** and the write path)
- Modify: `CrateBotCore/Sources/CrateBotCore/Tags/ID3Manager.swift` (write `TXXX:CRATEBOT_MIXHINT` when set)

- [ ] **Step 1:** When `appState.taggingPreferences.aiDescriptions.enabled`:
  - Build `VibeGenerationInputs` from `TaggingResult` + `TaggingResult.timingPrediction` (Chunk 1) + Cooccurrence stats loaded once at engine init.
  - Call `VibeGeneratorV2.generate(...)`.
  - Populate `tagsToWrite.vibeShort/.vibeDescription/.mixHint`.
- [ ] **Step 2: Error semantics** — generator failure logs the truncated raw response, does NOT block the rest of the tag write, and does NOT leave partial vibe fields populated (atomic: all three or none).
- [ ] **Step 3: Tests** — extend integration tests using a mock VibeChatClient: toggle off ⇒ vibe fields untouched; toggle on + success ⇒ all three written; toggle on + generator error ⇒ other tags still write, vibe fields nil.
- [ ] **Step 4: Commit** — `feat: wire VibeGeneratorV2 into tag pass behind opt-in toggle`.

### Task 4.3: Persistent generation cache

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Integrations/VibeCache.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Integrations/VibeCacheTests.swift`

- [ ] **Step 1: Failing tests** — key = SHA256(trackPath + stage1ModelVersion); hit returns stored result; miss returns nil; persists to `~/Library/Application Support/cratebot/vibe_cache.json`.
- [ ] **Step 2: Implement** as a value-typed JSON store (single dict on disk; load on first access; atomic write on save). Keep it simple — no eviction in v1, log when file passes 10 MB.
- [ ] **Step 3:** Wire into Task 4.2's flow: check cache first, generate on miss, save on success.
- [ ] **Step 4: Commit** — `feat: persistent vibe-generation cache keyed by (track, stage1 model version)`.

### Task 4.4: Settings UI

**Files:**
- Modify: `CrateBot/Views/SettingsPanel.swift` (~L122-130 — existing vibesShort/vibesLong toggles) — add the new AI descriptions toggle row.
- Modify: `CrateBot/Views/TaggingSettingsSheet.swift` (~L86-93) — same.

- [ ] **Step 1:** New section "AI descriptions" with bound toggle + tooltip "Generates short vibe, prose description, and DJ mix-context hint per track via Anthropic API. ~$0.01/track."
- [ ] **Step 2:** Greyed-out + tooltip when `KeychainManager.shared.exists(key: .anthropicAPIKey)` is false. Click opens existing API-key configuration sheet.
- [ ] **Step 3: Visual verification** via `xcodebuild build` + manual open (no UI test framework in this project). Document evidence.
- [ ] **Step 4: Commit** — `feat: Tagging Options gains AI descriptions toggle`.

**CHUNK 4 REVIEW GATE.**

---

## Chunk 5: Manual run + memory update

### Task 5.1: 50-track sample run

- [ ] **Step 1:** With toggle on, tag 50 of Noah's tracks. Verify success criteria from spec:
  - Zero chain-of-thought preambles in TCOM.
  - In a sliding window of 30 generated descriptions, no four-word phrase appears more than twice.
  - When Stage 2 Timing confidence > 0.5, mix hint references the actual Timing label; below threshold, mix hint frame is absent (not faked).
- [ ] **Step 2:** Update project memory with: new defaults, opt-in semantics, cost-per-track observed, and the v2 spec/plan paths.
- [ ] **Step 3:** Final push.

**Note for the manual run:** the Stage 2 model paired to the current CB5_v5 may produce thin Stage 2 confidences on most tracks (Stage 2 was healthy in the corrected eval — Combined 50.7% — so this should work). If many mix hints come out missing on the 50-track sample, that signals Stage 2 confidence calibration needs a closer look — not a bug in this chunk's code, but flag it for follow-up.

---

## Cross-chunk notes

- **Cooccurrence stats regeneration:** `tag_cooccurrence.json` was generated before the field-mapping fix and currently has empty `conditional["Peak"]` etc. The mix-hint feature degrades to "no hint" cleanly until those stats are regenerated. Regeneration is **out of scope** for this plan (the `generate_tag_cooccurrence.py` script already does it; user runs it when convenient). Plan flags this; chunks don't depend on it.
- **No new push until each chunk is reviewed.** Single PR-equivalent per chunk via direct push to master (project convention).
- **Test target absence:** the `aiDescriptions` Codable test uses the agent-runs-a-script pattern from `2026-06-13-id3field-decoder-tolerance.md` since CrateBot app target has no XCTest target.
