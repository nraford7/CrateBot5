# Vibe Generator v2: Audio-Grounded Descriptions Design

**Date:** 2026-06-13
**Status:** Validated with Noah (brainstorming session)

## Problem

Existing CrateBot4 wrote `TCOM` (short vibe) and `TIT3` (prose description) using a thin LLM prompt fed only metadata strings (genre, BPM, mood — all derived). Three problems visible in his current library:

1. **Chain-of-thought leakage** — `LOOKING AT THIS TRACK ANALYSIS:` / `PROCESS:` preambles wrote into `TCOM` when the parser failed to find the expected `VIBE:` marker.
2. **Template lock** — the same imagery (`"broken streetlight casting shadows..."`) repeats across hundreds of tracks because the input was low-entropy metadata, the temperature was low, and "Broken" (one of his Rhythm tags) propagated into the prose verbatim.
3. **No grounding in the actual audio** — descriptions feel generic because the LLM never sees the audio-grounded model outputs that Stage 1 and Stage 2 produce.

CrateBot5 currently has `NativeVibeGenerator.swift` but it is **unwired** — nothing in `TaggingView.writeTags` calls it. So today the app's tag pass leaves `TCOM`/`TIT3` untouched while legacy content accumulates from CrateBot4.

## Goal

Replace the legacy generator with a Stage 1–grounded description generator wired into the CrateBot5 tag pass, behind an opt-in toggle in Tagging Options. Three outputs per track:

- **`TCOM`** — short symbolic handle (4–5 all-caps words).
- **`TIT3`** — additive sensory/atmospheric description.
- **`MVNM`** — Movement Name / DJ-use guidance generated after the first two fields.

## Success criteria

- On a held-out sample of 50 of Noah's tracks: zero chain-of-thought preambles written; zero parse-failure silent fallbacks. Either a clean three-field result writes, or nothing writes for that track and the failure is logged.
- Visible imagery diversity: in any sliding window of 30 generated descriptions, no four-word phrase appears more than twice.
- Movement accuracy: the MVNM hint reads like DJ placement/use guidance, avoids repeating the completed `short`/`long`, and does not simply restate Timing/Genre/Mood tags.
- Cost transparency: Tagging Options shows the estimated `$/track` next to the toggle.

## Decisions (settled in brainstorming)

| Decision | Choice |
|---|---|
| Inputs | Stage 1 binary confidences + multi-class group probabilities + final predicted tag set + BPM/key/duration + track title + artist + album |
| Outputs | Short symbolic handle (TCOM) + sensory atmosphere (TIT3) + Movement/DJ-use hint (MVNM) |
| Diversity | Trust the model. Temperature 0.7. Diversify by feeding richer input gradient, not phrase ledgers or style rotation (deferred to v2 if template lock returns) |
| Run/overwrite | Opt-in toggle in Tagging Options panel; when on, overwrite legacy TCOM/TIT3 content |
| Model | Claude Sonnet 4 — the current default `"claude-sonnet-4-20250514"` in `AnthropicClient.swift:159`. (Bumping to Sonnet 4.5 is a separate one-line change; this spec leaves the default alone.) |

## Components

### 1. `VibeGenerationInputs` (new value type)

Pure data carrier — what the generator sees per track. Built by the tag-pass orchestrator from `TaggingResult` + Stage 2 prediction + co-occurrence stats. Fields:

- `binaryConfidences: [String: Float]` — every Stage 1 binary tag with its calibrated probability.
- `groupProbabilities: [String: [String: Float]]` — multi-class group distributions (BassType, VocalType).
- `predictedTags: UserTagPredictions` — what the user sees written to the file (Genre/Timing/Mood/Descriptive).
- `bpm: Float?`, `key: String?`, `durationSeconds: Float`.
- `title: String?`, `artist: String?`, `album: String?` — from ID3 TIT2/TPE1/TALB when available.
- `stage2Timing: (label: String, confidence: Float)?` — the Stage 2 Timing prediction.
- `cooccurrence: CooccurrenceContext?` — lift-ranked co-occurring tags for context. The movement hint is no longer gated on this; it is useful context when present.

### 2. `VibeGeneratorV2` (replaces `NativeVibeGenerator`)

Actor. Keeps the existing `AnthropicClient` injection pattern. Methods:

- `generate(inputs: VibeGenerationInputs) async throws -> VibeGenerationResult` returning all three outputs.
- Uses temperature 0.7, max tokens 600 for the description pass, max tokens 300 for the movement pass, model from `AnthropicClient.defaultModel`.
- Pass 1 strict JSON schema: `{"short": "...", "long": "..."}`.
- Pass 2 strict JSON schema: `{"mix_hint": "..."}`. Pass 2 sees the completed `short` and `long`.
- Semantic validation rejects bad-but-parseable JSON: `short` must be 4–5 all-caps words, `long` must avoid source/tag words and DJ-use phrasing, and `mix_hint` must contain DJ placement cues without repeating completed description tokens.

Replaces `NativeVibeGenerator` — old type renamed and stays as a deprecated shim for one version (to avoid breaking any in-flight tests), then deleted in a follow-up.

### 3. `CooccurrenceContext` extractor (new helper)

A small function `Cooccurrence.context(forTags: Set<String>, timing: String, stats: CooccurrenceStats) -> CooccurrenceContext?` that:

- Loads `tag_cooccurrence.json` (already produced by `generate_tag_cooccurrence.py`, already used by the booster). Schema is `{base_rates, conditional}` — symmetric `P(other | tag)` distributions plus tag base rates.
- For the given Timing label, returns the top-K (default 3) tags whose `P(tag | timing_label)` is highest (and significantly above `base_rate(tag)` to avoid trivial frequency artifacts), with a `support` count derived from the underlying counts.
- Returns `nil` if total support is below a threshold (default 3) — the silent-better-than-wrong rule from success criteria.
- The output describes *what the floor looks like* around this Timing label in Noah's library, not what comes before/after — the data does not support sequence claims.

### 4. Tagging pipeline integration (modify `TaggingView`)

In `CrateBot/Views/TaggingView.swift` around `try await id3Manager.writeTags(...)`:

- After `engine.analyze(url:)` produces `TaggingResult`, if `appState.taggingPreferences.aiDescriptions.enabled` (new field), build `VibeGenerationInputs` and call `VibeGeneratorV2.generate(...)`.
- Populate `tagsToWrite.vibeShort` (TCOM), `tagsToWrite.vibeDescription` (TIT3), and `tagsToWrite.mixHint` (MVNM) from the result. Existing AI frames are preserved if generation fails.
- Errors are logged and the track tags still write — vibe generation failure must not block the rest of the tag pass.

### 5. Settings UI (modify `TaggingSettingsSheet` / `SettingsPanel`)

**Codable migration note:** `TaggingPreferences` already has a careful manual `init(from:)` with legacy-key fallback. The new `aiDescriptions` field must follow the same pattern — `decodeIfPresent` with a default-disabled value, and an explicit `encode` line — not synthesized Codable. Otherwise existing saved preferences fail to load.


Add a new section "AI descriptions" with:

- Toggle bound to `aiDescriptions.enabled`.
- One line of explanatory text: "Generates short vibe, prose description, and mix-context hint per track using Anthropic API."
- Estimated cost ("~$0.01/track at current Sonnet 4 pricing") and a "Configure API key" link if `KeychainManager.shared.exists(key: .anthropicAPIKey)` is false. (Reality-checked: with ~30 binary confidences + multi-class group probs + predicted tags + title/artist/co-occurrence context, real input runs ~800–1200 tokens; at $3/$15 per Mtok that's ~$0.006–$0.009. Quote `$0.01` as a conservative-rounded user-facing number.)

### 6. ID3 write path (modify `ID3Manager` + `TagsToWrite`)

`TagsToWrite` gains `mixHint: String?`. `ID3Manager.writeTags` writes it as MVNM. The existing TCOM/TIT3 write paths are reused.

### 7. Persistent generation cache

Keyed by `(trackPath, stage1ModelVersion, modelName, generatorVersion)`. Simple JSON file at `~/Library/Application Support/CrateBot/vibe_cache.json`. A second tagging pass on the same track + same Stage 1 model/model/prompt contract doesn't re-pay. Invalidated when Stage 1, Anthropic model, or `VibeGeneratorV2.cacheVersion` changes.

## Out of scope (explicitly deferred)

- Phrase-ledger anti-repetition (revisit only if template lock returns).
- Style rotation across multiple voices.
- Hook generation (TXXX:WORK already lightly populated; separate concern).
- Batch UI to retroactively regenerate legacy CrateBot4 content on the full library (the opt-in toggle handles it organically as tracks get re-tagged).
- Mining true track-order predecessor/successor data from set history (would need DJ-set logs CrateBot doesn't have).
- Vibe-cache eviction policy: v1 keeps everything; revisit if the file grows past ~10 MB.
- Bumping the AnthropicClient default model to Sonnet 4.5: one-line change tracked separately.

## Error handling

- Missing API key: toggle disables itself with a tooltip "Set Anthropic API key in Preferences first."
- API failure: log, write the rest of the tags, continue. Per-track failures don't halt the batch.
- Parse failure (JSON schema mismatch): log the raw response truncated to 500 chars, write the rest of the tags, continue. **Never write a chain-of-thought preamble** — the v1 bug doesn't recur.

## Testing

- Unit: `VibeGenerationInputs` round-trips its fields; `Cooccurrence.context(...)` produces expected groups + returns nil under threshold; parser rejects malformed JSON; parser accepts the contract schema; parser refuses to fall back to raw text.
- Integration (mock AnthropicClient): tag pass with toggle off writes no TCOM/TIT3. Tag pass with toggle on calls generator and writes all three frames. Generator failure leaves the rest of the tag write intact.
- Manual: 50-track sample run, eyeball the descriptions for diversity and the mix hints for accuracy against the user's intuition.

## Build chunks (for the implementation plan)

1. `VibeGenerationInputs` + `CooccurrenceContext` extractor + tests. No LLM calls yet.
2. `VibeGeneratorV2` actor with prompt + JSON-schema parsing + tests (mock client).
3. Tagging pipeline integration: settings toggle, write-path wiring, error semantics, persistent cache.
4. Manual run + memory snapshot of the new defaults.
