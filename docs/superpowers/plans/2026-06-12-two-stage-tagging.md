# Two-Stage Tagging Implementation Plan

> **For Claude:** REQUIRED: Execute via Agency (`agency_create_project` → `agency_assign` per task), per Noah's workflow. Two-stage review (superpowers:requesting-code-review + fresheyes) at each CHUNK boundary, not per task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace single-window audio analysis and audio-only tag prediction with multi-window extraction (Stage 1, perception) plus a learned judgment layer for relational tags (Stage 2), per `docs/superpowers/specs/2026-06-12-two-stage-tagging-design.md`.

**Architecture:** Stage 1 keeps the existing per-tag BoostedTree classifiers but feeds them mean-pooled embeddings from 5 windows across the track. Stage 2 is a new set of BoostedTrees, one per Timing-category tag, whose inputs are Stage 1 confidences + multi-class probabilities + BPM + duration. Both stages share the category-complete negative-filtering rule.

**Tech Stack:** Swift 5.10 / SwiftPM, CoreML + CreateML, AVFoundation, XCTest. Python 3.13 for `scripts/accuracy_eval.py`. Test command: `cd CrateBotCore && swift test`.

**Baseline to beat:** 33.0% macro F1 (CB5_v5 + boost + optimized thresholds). Success: combined ≥ 45%.

**Working state note:** The repo has uncommitted SpecAugment changes in `EffNetExtractor.swift`, `CLAPExtractor.swift`, `TrainingCoordinator.swift`, `StatusBar.swift`. Commit or stash these BEFORE Chunk 1 (ask Noah which). Do not silently fold them into plan commits.

---

## Chunk 1: Windowed extraction + cache invalidation + eval dimension guard

### Task 1.1: Window fields on FeatureExtractionConfig

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/FeatureExtractionConfig.swift` (45 lines, read fully first)
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/FeatureExtractionConfigTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testDefaultConfigHasFiveWindows() {
    let config = FeatureExtractionConfig.default
    XCTAssertEqual(config.windowFractions, [0.1, 0.3, 0.5, 0.7, 0.9])
    XCTAssertEqual(config.clapWindowFractions, [0.25, 0.5, 0.75])
    XCTAssertEqual(config.windowDuration, 15.0)
}

func testWindowFieldsChangeConfigHash() {
    let a = FeatureExtractionConfig.default
    let b = FeatureExtractionConfig(
        featureConfig: a.featureConfig,
        segmentDuration: a.segmentDuration,
        segmentStartFractions: a.segmentStartFractions,
        windowDuration: 15.0,
        windowFractions: [0.5],          // different windows
        clapWindowFractions: [0.5]
    )
    XCTAssertNotEqual(a.configHash, b.configHash)
}
```

- [ ] **Step 2: Run, verify failure** — `cd CrateBotCore && swift test --filter FeatureExtractionConfigTests` → FAIL (no such members)

- [ ] **Step 3: Implement.** Add three stored properties with defaults in init so existing call sites compile unchanged:

```swift
/// Duration of each analysis window in seconds (EffNet/MAEST read the head of each window)
public let windowDuration: Double
/// Window start positions as fractions of track length (EffNet + Genres + MAEST)
public let windowFractions: [Double]
/// Window start positions for CLAP (10s input, fewer windows)
public let clapWindowFractions: [Double]
```

Update `init` (new params with defaults `15.0`, `[0.1, 0.3, 0.5, 0.7, 0.9]`, `[0.25, 0.5, 0.75]`) and `.default`. `configHash` already SHA256-encodes all Codable fields with sorted keys (line 34) — new fields invalidate the embedding cache automatically. **Do not add a separate version integer.** Keep `segmentDuration`/`segmentStartFractions` for now (removed in Task 1.3 when the training path stops using them — check then whether anything else references them; delete fully if not).

- [ ] **Step 4: Run, verify pass** — also run full suite: `swift test` (375 tests green)
- [ ] **Step 5: Commit** — `feat: window fields on FeatureExtractionConfig (cache-invalidating)`

### Task 1.2: Windowed extraction in CombinedFeatureExtractor

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/Audio/CombinedFeatureExtractor.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/Audio/CombinedFeatureExtractorWindowingTests.swift` (new)

- [ ] **Step 1: Write failing tests** (synthetic buffers; see `TrainingPipeline40PercentTests.testCombinedFeatureExtractorWithSyntheticAudio` for the synthetic-audio helper pattern):

```swift
func testSliceWindowsProducesRequestedCount() throws {
    // 180s of 16kHz audio → 5 windows of 15s at the configured fractions
    let buffer = makeSyntheticBuffer(seconds: 180, sampleRate: 16000)
    let windows = CombinedFeatureExtractor.sliceWindows(
        buffer: buffer, fractions: [0.1, 0.3, 0.5, 0.7, 0.9], duration: 15.0)
    XCTAssertEqual(windows.count, 5)
    XCTAssertEqual(windows[0].frameLength, AVAudioFrameCount(15.0 * 16000))
}

func testShortTrackCollapsesToFewerWindows() throws {
    // 20s track: windows overlap heavily → deduplicated to distinct starts, min 1
    let buffer = makeSyntheticBuffer(seconds: 20, sampleRate: 16000)
    let windows = CombinedFeatureExtractor.sliceWindows(
        buffer: buffer, fractions: [0.1, 0.3, 0.5, 0.7, 0.9], duration: 15.0)
    XCTAssertGreaterThanOrEqual(windows.count, 1)
    XCTAssertLessThan(windows.count, 5)
}

func testMeanPoolAverages() {
    let pooled = CombinedFeatureExtractor.meanPool([[1, 2], [3, 4]])
    XCTAssertEqual(pooled, [2, 3])
}

func testWindowedExtractionOutputDimensionUnchanged() async throws {
    let extractor = try CombinedFeatureExtractor(config: .effnetPlusGenres)
    let buffer = makeSyntheticBuffer(seconds: 120, sampleRate: 16000)
    let vector = try await extractor.extractWindowed(
        from: buffer, config: FeatureExtractionConfig.default)
    XCTAssertEqual(vector.count, 1680)   // same shape as single-shot
}
```

- [ ] **Step 2: Run, verify FAIL**
- [ ] **Step 3: Implement.** Three additions to `CombinedFeatureExtractor`:

```swift
/// Slice a buffer into windows at the given start fractions.
/// Windows are clamped to the buffer; starts closer than duration/2 to a
/// previous window are dropped (short-track collapse). Always returns >= 1 window.
static func sliceWindows(
    buffer: AVAudioPCMBuffer, fractions: [Double], duration: Double
) -> [AVAudioPCMBuffer] {
    let sampleRate = buffer.format.sampleRate
    let totalFrames = Int(buffer.frameLength)
    let windowFrames = min(Int(duration * sampleRate), totalFrames)
    guard windowFrames > 0 else { return [buffer] }

    var startFrames: [Int] = []
    let minGap = windowFrames / 2
    for fraction in fractions {
        let start = min(Int(Double(totalFrames) * fraction), totalFrames - windowFrames)
        let clamped = max(0, start)
        if let last = startFrames.last, clamped - last < minGap { continue }
        startFrames.append(clamped)
    }
    if startFrames.isEmpty { startFrames = [0] }

    return startFrames.compactMap { start in
        copySlice(of: buffer, fromFrame: start, frameCount: windowFrames)
    }
}

static func meanPool(_ vectors: [[Float]]) -> [Float] {
    guard let first = vectors.first else { return [] }
    var sum = [Float](repeating: 0, count: first.count)
    for v in vectors where v.count == first.count {
        for i in 0..<v.count { sum[i] += v[i] }
    }
    let n = Float(vectors.count)
    return sum.map { $0 / n }
}
```

`copySlice` is a private helper creating a new `AVAudioPCMBuffer` and memcpy-ing the frame range (mirror the buffer-copy pattern in `AudioAnalyzer.swift`).

`extractWindowed(from:config:)` — the new public entry point. **Pool per extractor block, then concatenate** (CLAP has a different window count than EffNet):

```swift
public func extractWindowed(
    from buffer: AVAudioPCMBuffer,
    config: FeatureExtractionConfig,
    augmentationConfig: AudioAugmenter.AugmentationConfig? = nil
) async throws -> [Float] {
    let windows = Self.sliceWindows(
        buffer: buffer, fractions: config.windowFractions, duration: config.windowDuration)

    var embeddingsPerWindow: [[Float]] = []
    var genresPerWindow: [[Float]] = []
    var maestPerWindow: [[Float]] = []

    for window in windows {
        let (emb, gen) = try await effnetExtractor.extractWithGenres(
            from: window, augmentationConfig: augmentationConfig)
        embeddingsPerWindow.append(emb)
        genresPerWindow.append(gen)
        if let maest = maestExtractor {
            maestPerWindow.append(try await maest.extract(
                from: window, augmentationConfig: augmentationConfig))
        }
    }

    var combined = Self.meanPool(embeddingsPerWindow) + Self.meanPool(genresPerWindow)

    if let clap = clapExtractor {
        let clapWindows = Self.sliceWindows(
            buffer: buffer, fractions: config.clapWindowFractions, duration: config.windowDuration)
        var clapPerWindow: [[Float]] = []
        for window in clapWindows {
            let samples = extractFloatSamples(from: window)
            clapPerWindow.append(try await clap.extract(
                from: samples, sampleRate: Double(window.format.sampleRate),
                augmentationConfig: augmentationConfig))
        }
        combined += Self.meanPool(clapPerWindow)
    }

    if !maestPerWindow.isEmpty {
        combined += Self.meanPool(maestPerWindow)
    }
    return combined
}
```

Note the block order must match the existing layout exactly: EffNet, Genres, CLAP, MAEST (zero-shot matcher slices `[1680..<2192]` for CLAP — `TaggingEngine.swift:532`). Respect `actualConfig`: skip CLAP/MAEST blocks the same way `extract(from:augmentationConfig:)` does.

- [ ] **Step 4: Run, verify PASS** + full suite green
- [ ] **Step 5: Commit** — `feat: multi-window extraction with per-block mean pooling`

### Task 1.3: One extraction path for training and inference

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift` (segment logic ~L791-829; reads `segmentStartFractions`)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` (single-buffer extraction ~L303-308 and the `analyze(url:)` path)

- [ ] **Step 1: Find every call site** — `grep -rn "segmentStartFractions\|loadAudioSegments\|extract(from:" CrateBotCore/Sources/`
- [ ] **Step 2: TrainingDataCollector** replaces its three-segment loop with one `extractWindowed(from:config:augmentationConfig:)` call on the full buffer. Delete the dead segment helpers. The augmentation config still passes through (SpecAugment applies per window inside the extractor).
- [ ] **Step 3: TaggingEngine** `analyze(url:)` and `analyze(buffer:)` call `extractWindowed` with the same `FeatureExtractionConfig` (inject it; default `.default`). Inference and training now share one code path.
- [ ] **Step 4: Remove `segmentDuration`/`segmentStartFractions`** from `FeatureExtractionConfig` if nothing references them after steps 2-3 (this also changes `configHash` — fine, cache invalidates once, which we want anyway).
- [ ] **Step 5: Run full suite; fix broken tests** — tests that asserted three-segment behavior should be rewritten against `extractWindowed`, not deleted.
- [ ] **Step 6: Commit** — `feat: unify training and inference on windowed extraction path`

### Task 1.4: Dimension guard in accuracy_eval.py

**Files:**
- Modify: `scripts/accuracy_eval.py` (cache load ~L49, feature rows ~L104, ~L128; metadata at ~L196)

- [ ] **Step 1:** After loading the cache and metadata, assert every cached vector length equals `metadata['featureDimension']`:

```python
expected_dim = metadata["featureDimension"]
bad = [t["id"] for t in tracks if len(t["features"]) != expected_dim]
if bad:
    sys.exit(
        f"FATAL: {len(bad)} cached vectors do not match model featureDimension "
        f"{expected_dim} (first: {bad[0]}). The embedding cache is stale — "
        f"re-extract before evaluating. Refusing to produce garbage numbers."
    )
```

- [ ] **Step 2:** Manual check: run against the current (2192) model + cache → passes; truncate one cache entry in a copy → exits with the FATAL message.
- [ ] **Step 3: Commit** — `fix: accuracy_eval refuses dimension-mismatched cache`

**CHUNK 1 REVIEW GATE:** combined diff review (requesting-code-review + fresheyes), fix findings, both clean before Chunk 2.

---

## Chunk 2: TagStageRegistry + category-complete filtering

### Task 2.1: TagStageRegistry

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/TagStageRegistry.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TagStageRegistryTests.swift` (new)

- [ ] **Step 1: Failing tests** — `stage(forCategory: "Timing") == .judgment`; Genre/Mood/Descriptive → `.perception`; unknown category → `.perception` (safe default); `categories(in: .judgment) == ["Timing"]`.
- [ ] **Step 2: Implement** — small and boring on purpose:

```swift
/// Maps tag categories to pipeline stages.
/// Stage 1 (perception): tags predictable from audio alone.
/// Stage 2 (judgment): tags encoding DJ intent, learned from Stage 1 outputs.
public enum TagStage: String, Codable, Sendable {
    case perception
    case judgment
}

public struct TagStageRegistry: Sendable {
    private let categoryToStage: [String: TagStage]

    public init(categoryToStage: [String: TagStage] = Self.defaultMapping) {
        self.categoryToStage = categoryToStage
    }

    public static let defaultMapping: [String: TagStage] = [
        "Genre": .perception,
        "Mood": .perception,
        "Descriptive": .perception,
        "Timing": .judgment,
    ]

    public func stage(forCategory category: String) -> TagStage {
        categoryToStage[category] ?? .perception
    }

    public func categories(in stage: TagStage) -> [String] {
        categoryToStage.filter { $0.value == stage }.map(\.key).sorted()
    }
}
```

- [ ] **Step 3: Run, PASS, commit** — `feat: TagStageRegistry maps categories to pipeline stages`

### Task 2.2: Category-complete filtering in BinaryTrainingDataGenerator

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift` (72 lines — read fully)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift` (TaggedTrack construction site, ~L327)
- Test: `CrateBotCore/Tests/CrateBotCoreTests/BinaryTrainingDataGeneratorTests.swift`

- [ ] **Step 1:** Extend `TaggedTrack` with `public let tagsByCategory: [String: Set<String>]` (default `[:]` in both inits — existing tests compile unchanged). `TrainingDataCollector.convertToTagSet` already knows each tag's source ID3 field → category (genre/TCON, timing/TALB, mood/TIT1, descriptive/COMM per the field mapping at `TrainingDataCollector.swift:443-446`); populate the dictionary there.
- [ ] **Step 2: Failing tests** — the truth table:

```swift
func testTrackWithoutCategoryTagsIsExcludedFromNegatives() {
    let tagged   = TaggedTrack(id: "a", tags: ["Peak"], features: nil,
                               tagsByCategory: ["Timing": ["Peak"]])
    let votedNo  = TaggedTrack(id: "b", tags: ["Build"], features: nil,
                               tagsByCategory: ["Timing": ["Build"]])
    let untagged = TaggedTrack(id: "c", tags: ["House"], features: nil,
                               tagsByCategory: ["Genre": ["House"]])
    let gen = BinaryTrainingDataGenerator(minPositiveExamples: 1)
    let result = gen.generateTrainingData(
        for: "Peak", category: "Timing",
        from: [tagged, votedNo, untagged])!
    XCTAssertEqual(result.positive.map(\.id), ["a"])
    XCTAssertEqual(result.negative.map(\.id), ["b"])     // c excluded: unknown, not negative
    XCTAssertEqual(result.excludedCount, 1)
}
```

- [ ] **Step 3: Implement.** New signature (old one stays as a deprecated shim calling the new one with `category: nil` = old behavior, so the migration is observable):

```swift
public struct TrainingDataResult {
    public let positive: [TaggedTrack]
    public let negative: [TaggedTrack]
    public let excludedCount: Int   // unknowns: no tags in this category
}

public func generateTrainingData(
    for tagName: String,
    category: String?,
    from tracks: [TaggedTrack]
) -> TrainingDataResult? {
    let positive = tracks.filter { $0.tags.contains(tagName) }
    let eligible: [TaggedTrack]
    let excluded: Int
    if let category = category {
        let considered = tracks.filter { !($0.tagsByCategory[category] ?? []).isEmpty }
        eligible = considered.filter { !$0.tags.contains(tagName) }
        excluded = tracks.count - considered.count
    } else {
        eligible = tracks.filter { !$0.tags.contains(tagName) }
        excluded = 0
    }
    guard positive.count >= minPositiveExamples, !eligible.isEmpty else { return nil }
    let maxNegatives = Int(Double(positive.count) * maxNegativeRatio)
    return TrainingDataResult(
        positive: positive,
        negative: Array(eligible.shuffled().prefix(maxNegatives)),
        excludedCount: excluded)
}
```

- [ ] **Step 4:** Thread `category` through from `ModelTrainer`/`TrainingCoordinator` call sites (they hold `categorizedTags` — see `TrainingCoordinator.swift:802-815` for the tag→category lookup pattern). Log per tag: `"<tag>: N positive / M trusted negative / K excluded-unknown"`. Tags returning nil are collected and reported in the training summary (NOT silently skipped) — surface the list in `TrainingResult`.
- [ ] **Step 5: Run full suite; commit** — `feat: category-complete negative filtering (absence = unknown)`

**CHUNK 2 REVIEW GATE** (same two-stage protocol).

---

## Chunk 3: JudgmentDataGenerator + Stage 2 training

### Task 3.1: JudgmentFeatureVector — the Stage 2 input contract

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/JudgmentFeatures.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/JudgmentFeaturesTests.swift` (new)

- [ ] **Step 1: Failing tests** — deterministic column order; BPM sentinel:

```swift
func testColumnOrderIsDeterministicAndSorted() {
    let v = JudgmentFeatureVector(
        binaryConfidences: ["Dark": 0.8, "Aggressive": 0.5],
        groupProbabilities: ["BassType": ["Punchy": 0.7, "Walking": 0.3]],
        bpm: 128, durationSeconds: 372)
    XCTAssertEqual(v.columnNames,
        ["bin_Aggressive", "bin_Dark", "grp_BassType_Punchy", "grp_BassType_Walking",
         "bpm", "duration"])
    XCTAssertEqual(v.values, [0.5, 0.8, 0.7, 0.3, 128, 372])
}

func testMissingBPMUsesSentinel() {
    let v = JudgmentFeatureVector(binaryConfidences: [:], groupProbabilities: [:],
                                  bpm: nil, durationSeconds: 200)
    XCTAssertEqual(v.values[v.columnNames.firstIndex(of: "bpm")!], -1.0)
}
```

- [ ] **Step 2: Implement** a struct that flattens to `(columnNames: [String], values: [Float])` with sorted keys (`bin_` prefix for binary confidences, `grp_<group>_<class>` for multi-class, then `bpm`, `duration`). Sorted order is the schema — Stage 2 training and inference must produce identical columns or predictions are garbage. Encode `columnNames` into Stage 2 model metadata so a mismatch is detectable at load.
- [ ] **Step 3: PASS, commit** — `feat: JudgmentFeatureVector defines Stage 2 input schema`

### Task 3.2: JudgmentDataGenerator

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/JudgmentDataGenerator.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/JudgmentDataGeneratorTests.swift` (new)

- [ ] **Step 1: Failing tests** with mock classifier outputs (protocol-injected, no CoreML in unit tests): builds one row per track from cached features; targets filtered by category-complete rule (reuse Task 2.2 logic for Timing category); tracks with no cached features are skipped and counted.
- [ ] **Step 2: Implement.** Inputs: `[TaggedTrack]` (with cached feature vectors), a `Stage1Predictor` protocol (`func confidences(features: [Float]) async throws -> (binary: [String: Float], groups: [String: [String: Float]])` — production impl wraps the loaded `TagClassifier`s + `MultiClassClassifier`s; BPM via `ID3Manager` TBPM read (~L158); duration from the audio file's `AVAudioFile.length / sampleRate` captured at collection time (add to `CachedFeatures` if absent — check `Models.swift`). Output: `(rows: [JudgmentRow], skipped: Int)` where `JudgmentRow = (features: JudgmentFeatureVector, labels: Set<String>, trackID: String)`.
- [ ] **Step 3: PASS, commit** — `feat: JudgmentDataGenerator builds Stage 2 training rows`

### Task 3.3: Stage 2 training in ModelTrainer + two-phase TrainingCoordinator

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift` (DataFrame builder ~L280-320 is the pattern to follow)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift` (+`stage1ModelVersion: String?`, +`judgmentColumnNames: [String]?`)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCheckpoint.swift` (+phase marker)
- Test: extend `ModelTrainerTests` + `TrainingCoordinatorTests`

- [ ] **Step 1: Failing tests** — coordinator runs Phase A then Phase B; checkpoint written after Phase A resumes into Phase B without retraining Stage 1; metadata records `stage1ModelVersion` and `judgmentColumnNames`; Stage 2 model files named `<tag>_judgment.mlmodel`.
- [ ] **Step 2: Implement Stage 2 training**: per Timing tag, build an `MLDataTable` from `JudgmentRow`s (columns from `JudgmentFeatureVector.columnNames`, label column from category-complete-filtered targets), train `MLBoostedTreeClassifier` with the existing config (`TrainingConfig.swift:41-46` defaults are fine for ~60 dims — do NOT copy the augmentation path; no mixup/noise on judgment features).
- [ ] **Step 3: Implement Phase B in TrainingCoordinator**: after Phase A completes, load the just-trained Stage 1 models, run `JudgmentDataGenerator` over the library (cached features only — no audio re-extraction), train Stage 2, write paired metadata. Checkpoint gains `case phaseACompleted` so a crash resumes into Phase B. **Pairing enforcement:** Phase B refuses to run against a Stage 1 version other than the one in the checkpoint.
- [ ] **Step 4: Run full suite; commit** — `feat: two-phase training — Stage 2 judgment models paired to Stage 1`

**CHUNK 3 REVIEW GATE.**

---

## Chunk 4: Inference rewire + thresholds + eval

### Task 4.1: Threshold defaults by category

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:163` (the `0.85` default) and threshold lookups at `:487`, `:516`, `:736`
- Test: extend `TaggingEngineTests`

- [ ] **Step 1: Failing tests** — tag with no tuned threshold resolves to its category default (Genre 0.7, Mood 0.55, Descriptive 0.55); tuned `tagThresholds` entries still win.
- [ ] **Step 2: Implement** `defaultThreshold(forCategory:)` using metadata's `tags: [String: [String]]` (category → tags, `ModelMetadata.swift:39`) for the tag→category lookup; replace the bare `classificationThreshold` fallback at the three sites. Keep `classificationThreshold` as the final fallback for uncategorized tags, but change its default from 0.85 to 0.7.
- [ ] **Step 3: PASS, commit** — `fix: per-category threshold defaults replace global 0.85`

### Task 4.2: Stage 2 inference in TaggingEngine

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` (model loading ~L304-339; decision pipeline L461-564)
- Test: extend `TaggingEngineTests` (mock judgment models via the loading path)

- [ ] **Step 1: Failing tests** — `_judgment` models load into a separate collection; relational predictions come from Stage 2 only; when Stage 2 is missing or `stage1ModelVersion` mismatches, relational tags are absent and `TaggingResult` carries `judgmentAvailable: false` (no stale judgments); column schema mismatch → judgment skipped with a logged error, never garbage predictions.
- [ ] **Step 2: Implement.** Loading: files suffixed `_judgment` go to `judgmentClassifiers` (exclude from `binaryModelFiles` filter at L304-307 alongside `_multiclass`). Decision flow after the existing Pass 3:

```
Pass 4 (judgment): build JudgmentFeatureVector from
  rawProbabilities (calibrated, pre-boost) + multi-class group probabilities
  + BPM + duration → each judgment classifier predicts → apply Stage 2
  per-tag thresholds (tagThresholds lookup, Timing default 0.55 until tuned)
```

Timing tags are removed from the binary/zero-shot/fallback paths (they are Stage 2's exclusive domain — use `TagStageRegistry` to partition).
- [ ] **Step 3: Booster scope** — `useCooccurrenceBoosting` defaults to `false`; when enabled, `booster.adjust` receives only perception-stage probabilities (filter the dictionary by stage before the call at L480).
- [ ] **Step 4: Multi-class confidence gate** — at L516-520, in addition to the threshold, require separation: `prediction.confidence - secondBest >= 0.15`, else no tag from that group (extend `MultiClassClassifier.Prediction` to expose the runner-up probability).
- [ ] **Step 5: Run full suite; commit** — `feat: Stage 2 judgment inference; booster scoped to perception`

### Task 4.3: Two-stage evaluation

**Files:**
- Modify: `scripts/accuracy_eval.py`
- Modify: `scripts/generate_tag_cooccurrence.py` only if eval imports break (verify, don't refactor)

- [ ] **Step 1:** Add `--stage-aware` mode: read `judgmentColumnNames` + category mapping from model metadata; split tags into perception/judgment sets; for judgment tags, build the Stage 2 input from the perception models' outputs exactly as `TaggingEngine` does (calibrated, pre-boost) and run the `_judgment` CoreML models via `coremltools`. Report three macro F1 numbers: Stage 1, Stage 2, combined.
- [ ] **Step 2:** Holdout: stratified per tag, 20%, `random.seed(42)` fixed; the SAME holdout evaluates both stages (Stage 2 thresholds are tuned only on this holdout — the in-sample mitigation from the spec).
- [ ] **Step 3:** `--optimize` tunes per-tag thresholds on final pipeline scores (post-calibration; post-judgment for Stage 2 tags) and writes `tag_thresholds.json` in the existing nested format (`TaggingEngine.swift:243-261` documents both accepted formats).
- [ ] **Step 4:** Run against the retrained models. Record in the run log: Stage 1 F1, Stage 2 F1, combined vs **33.0% baseline**. Success gate: combined ≥ 45%.
- [ ] **Step 5: Commit** — `feat: two-stage evaluation with stratified holdout`

### Task 4.4: Full retrain + verification (Noah-in-the-loop)

- [ ] **Step 1:** Confirm with Noah before starting: cache invalidates (configHash changed), full re-extraction of ~2,250 tracks × 5 windows ≈ overnight run; this is also the pending MAEST retrain.
- [ ] **Step 2:** After training: verify new model metadata — `featureDimension == 2960`, `stage1ModelVersion` set, `judgmentColumnNames` present, `_judgment` models on disk.
- [ ] **Step 3:** Run `python3 scripts/accuracy_eval.py --stage-aware --optimize --boost`; capture the three F1 numbers; compare to 33.0%.
- [ ] **Step 4:** @superpowers:verification-before-completion — no success claims without the eval output in hand. Update the project memory with the new numbers.

**CHUNK 4 REVIEW GATE**, then final branch integration per @superpowers:finishing-a-development-branch.

---

## Execution notes for Agency

- Project structure mirrors chunks: 4 chunks, tasks as listed. One Agency task per plan task.
- Each task's evaluator checks: tests written before implementation, full suite green, commit made, no scope creep into later tasks.
- Review cap: 5 passes total per chunk (2 plan + 3 implementation). If pass 5 still finds blockers, STOP and re-plan.
- The uncommitted SpecAugment work (see header) must be resolved before Chunk 1 starts.
- Build/test command: `cd CrateBotCore && swift test`. UI app build not required for chunks 1-3; chunk 4 task 4.4 runs the real app for training.
