# Descriptive Sub-Category Granularity Implementation Plan

> **For Claude:** REQUIRED: Execute via Agency. Chunk-boundary two-stage review. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Apply the category-complete training-data filter at descriptive **sub-category** granularity (BassType, Rhythm, Style, Vibes, Instruments, VocalType), not just top-level Descriptive. A track is a trusted negative for "Walking" only if it carries at least one BassType tag — not merely any descriptive tag.

**Why:** Noah's library doesn't always tag BassType or Rhythm. Under the top-level rule, a track with only "Dark, Funky" (Vibes) counts as a trusted negative for "Walking" (BassType) — false-negative noise the model learns from. This is the deferred lever named in `docs/superpowers/specs/2026-06-12-two-stage-tagging-design.md` section 3 ("one-line change in the filter, flagged as a known lever").

**Spec reference:** 2026-06-12-two-stage-tagging-design.md component 3 (category-complete filtering). No new spec needed — this realizes the documented lever.

**Architecture:** A new `effectiveCategory(for tag:, topLevel:)` resolver folds `DescriptiveTagMapping.subCategory` into the category logic at two sites — the collector populates `tagsByCategory` keyed by effective category, the trainer's tag→category lookup uses the same resolver. Custom descriptive tags (no known sub-category) stay under "Descriptive" — the user's mapping is the source of truth.

**Tech Stack:** Swift / SwiftPM / XCTest. Baseline: 455 tests, 0 failures.

---

## Chunk 1: sub-category-granular filtering

### Task 1.1: Effective-category resolver + collector + trainer threading

**Files (anchors verified by plan review):**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/DescriptiveTagMapping.swift` (add static helper after L97)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift` (~L1062 — descriptive tag insertion)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift` (~L274-285 — `tagToCategory` build)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ExperimentRunner.swift` (~L246-261 — `deriveTagCategories`)
- **Audit (no change expected, but VERIFY)**: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift` at L587-592 (training-path tag→category build feeding `isJudgmentTag`) and L1209-1212 (`groupTagsByCategory`). These read `options.tagsByCategory` which is now sub-category-keyed. Verify: (i) the stage registry still classifies BassType/Rhythm/etc. as **perception** stage (not judgment) — they're descriptive sub-categories, perception only; (ii) `groupTagsByCategory`'s output grouping still produces a sensible structure when keys are sub-categories instead of "Descriptive". If either misbehaves, fix HERE not later.
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/DescriptiveTagMappingTests.swift`, `BinaryTrainingDataGeneratorTests.swift`, `TrainingDataCollectorTests.swift`, plus a `TrainingCoordinatorTests` check that `isJudgmentTag` still returns false for descriptive sub-category tags.

- [ ] **Step 1: Failing tests**

```swift
// DescriptiveTagMappingTests
func testEffectiveCategoryResolvesDescriptiveSubCategories() {
    XCTAssertEqual(DescriptiveTagMapping.effectiveCategory(for: "Walking", topLevel: "Descriptive"), "BassType")
    XCTAssertEqual(DescriptiveTagMapping.effectiveCategory(for: "Funky",   topLevel: "Descriptive"), "Vibes")
    XCTAssertEqual(DescriptiveTagMapping.effectiveCategory(for: "Broken",  topLevel: "Descriptive"), "Rhythm")
    XCTAssertEqual(DescriptiveTagMapping.effectiveCategory(for: "House",   topLevel: "Genre"), "Genre")
    XCTAssertEqual(DescriptiveTagMapping.effectiveCategory(for: "Peak",    topLevel: "Timing"), "Timing")
    XCTAssertEqual(DescriptiveTagMapping.effectiveCategory(for: "Groovy",  topLevel: "Descriptive"), "Descriptive")
    // custom tag, no known sub-category → stays under top-level
}

// BinaryTrainingDataGeneratorTests
func testSubCategoryCompletenessExcludesTracksWithoutBassType() {
    let withBass    = TaggedTrack(id: "a", tags: ["Walking"],          tagsByCategory: ["BassType": ["Walking"]])
    let votedNoBass = TaggedTrack(id: "b", tags: ["Punchy"],           tagsByCategory: ["BassType": ["Punchy"]])
    let onlyVibe    = TaggedTrack(id: "c", tags: ["Dark", "Funky"],    tagsByCategory: ["Vibes": ["Dark", "Funky"]])

    let gen = BinaryTrainingDataGenerator(minPositiveExamples: 1)
    let result = gen.generateTrainingData(for: "Walking", category: "BassType", from: [withBass, votedNoBass, onlyVibe])!
    XCTAssertEqual(result.positive.map(\.id), ["a"])
    XCTAssertEqual(result.negative.map(\.id), ["b"])
    XCTAssertEqual(result.excludedCount, 1)        // c excluded as unknown for BassType
}
```

- [ ] **Step 2: Run, verify FAIL** — `cd CrateBotCore && swift test --filter DescriptiveTagMappingTests`

- [ ] **Step 3: Implement the resolver** (one static helper):

```swift
// DescriptiveTagMapping.swift
/// Resolve the effective category for a tag: sub-category for known descriptive tags,
/// top-level otherwise. Used by the collector and trainer so category-complete filtering
/// applies at sub-category granularity for descriptive tags.
public static func effectiveCategory(for tag: String, topLevel: String) -> String {
    if topLevel == "Descriptive", let sub = subCategory(for: tag) {
        return sub.rawValue
    }
    return topLevel
}
```

- [ ] **Step 4: Thread it through.** Three call sites:

  - `TrainingDataCollector.convertToTags` ~L1062: replace `byCategory["Descriptive", default: []].insert(tag)` with `byCategory[DescriptiveTagMapping.effectiveCategory(for: tag, topLevel: "Descriptive"), default: []].insert(tag)`.
  - `ModelTrainer.trainModelsWithReport` (where `tagToCategory` is built from `categorizedTags`): wrap each tag insert with `effectiveCategory(for: tag, topLevel: category)`. Use sorted keys + first-wins per the existing convention.
  - `ExperimentRunner.deriveTagCategories`: same pattern.

- [ ] **Step 4b: Add the two additional tests the reviewer flagged:**

  - `TrainingDataCollectorTests`: a track with a single `"Walking"` descriptive tag produces `tagsByCategory["BassType"]` containing "Walking" and does NOT produce a "Descriptive" key for that tag. A custom tag (e.g. "Groovy") still lands under "Descriptive".
  - `TrainingCoordinatorTests`: `isJudgmentTag("Walking")` returns false (BassType is perception, not judgment) when the registry is built from sub-category-keyed `options.tagsByCategory`.

- [ ] **Step 5: Run full suite — 455 → 460 (5 new), 0 failures expected.** If any existing test relied on "Descriptive" as the descriptive negative-eligibility category, rewrite it to assert the new sub-category granularity (do not weaken to keep it green).

- [ ] **Step 6: Commit** — `feat: category-complete filtering at descriptive sub-category granularity` + Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>

### Acceptance criteria for the chunk

- Three new tests pass.
- A track with only Vibes tags is NOT a trusted negative for any BassType/Rhythm/Instruments/Style/VocalType tag.
- Custom descriptive tags (not in `DescriptiveTagMapping.mapping`) still fall back to "Descriptive" category and behave under the old top-level rule.
- The training summary's `skippedTagDetails` correctly reports BassType/Rhythm tags that lack trusted negatives — visibility into the same gap Noah just asked about.
- Multi-class BassType/VocalType training is structurally unaffected (it already filters tracks lacking class tags) — no test changes there required.
- Full suite green; app target builds.

**CHUNK 1 REVIEW GATE** (two-stage: requesting-code-review + independent no-context subagent).

---

## Build notes for Agency

- One Agency task; one commit; one chunk-review pass.
- Review cap unchanged from /do-it (10 passes; backstop).
- Touch nothing outside the four files named above without surfacing the reason first.
- This change applies on the NEXT training run; it does not require a separate retrain (Noah's overnight run picks it up automatically if it lands before he starts).
