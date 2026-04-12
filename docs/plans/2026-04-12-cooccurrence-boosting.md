# Post-hoc Co-occurrence Boosting Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boost tagging accuracy by correcting individual classifier outputs using tag co-occurrence statistics from the training data.

**Architecture:** A pure Swift post-processing step inserted into TaggingEngine after trained classifiers run. Uses pre-computed tag statistics (base rates + conditional probabilities) bundled as a JSON resource. Adjusts each tag's probability based on what OTHER tags were confidently predicted. Zero model retraining required. Fully reversible. Opt-in via a boolean flag.

**Tech Stack:** Swift, Accelerate (cosine similarity / math), JSON resource bundling

---

## Root Observation

Analysis of the current 2,247-track library shows:
- **218 strong positive co-occurrences** (P(B|A) ≥ 0.5 with support ≥ 20)
- **45 strong negative correlations** (tags that rarely coexist when you'd expect them to)
- **9.4 tags per track on average** — tags are densely entangled, not independent
- **Techno ⟹ Driving with 98.5% confidence** — binary classifiers can't capture this
- **Aggressive ⊥ Happy** — 1 joint occurrence vs 192 expected — model currently can predict both

Binary BoostedTree classifiers treat each tag as independent. Boosting uses the dependency structure as a free accuracy gain.

## Approach: Probabilistic Score Adjustment

For each tag A with raw classifier probability P(A), compute an adjusted probability using confident co-occurring tags:

```
adjusted(A) = σ(logit(P(A)) + Σ_B in strong_tags λ · log(P(A|B) / P(A)))
```

Where:
- `strong_tags` = tags B with P(B) ≥ 0.8 (high-confidence predictions)
- `P(A|B) / P(A)` is the **lift** — how much B's presence raises A's probability
- `λ` is the boost weight (tunable, default 0.5)
- Only boost when lift > 1.5 or penalize when lift < 0.5
- Cap the adjustment so a single strong signal can't dominate

This is essentially a one-step Naive Bayes correction using the learned tag co-occurrence structure.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `CrateBotCore/Sources/CrateBotCore/Resources/tag_cooccurrence.json` | Create | Bundled stats: base rates + conditional probabilities |
| `CrateBotCore/Sources/CrateBotCore/ML/TagCooccurrenceBooster.swift` | Create | Core booster struct with score adjustment logic |
| `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` | Modify | Load booster in init, apply in analyze() before threshold |
| `CrateBotCore/Package.swift` | Modify | Bundle the JSON resource |
| `CrateBotCore/Tests/CrateBotCoreTests/ML/TagCooccurrenceBoosterTests.swift` | Create | Unit tests for stat loading and score adjustment |
| `scripts/generate_tag_cooccurrence.py` | Create | Analyzes ID3 tags in the library to produce the JSON |
| `scripts/accuracy_eval.py` | Modify | Add `--boost` flag to evaluate with boosting enabled |

---

## JSON Resource Format

```json
{
  "version": 1,
  "total_tracks": 2247,
  "base_rates": {
    "House": 0.6016,
    "Driving": 0.4277,
    "Techno": 0.0294,
    ...
  },
  "conditional": {
    "Techno": { "Driving": 0.9848, "House": 0.0303 },
    "Afro": { "House": 0.8885, "Congas": 0.7121 },
    ...
  }
}
```

Only stores conditional probabilities where the lift (P(B|A) / P(B)) is ≥ 1.5 or ≤ 0.5 — the rest are noise.

---

## Chunk 1: Generate and Bundle Statistics

### Task 1: Create statistics generator script

**Files:**
- Create: `scripts/generate_tag_cooccurrence.py`

- [ ] **Step 1: Write the generator**

```python
#!/usr/bin/env python3
"""
Generate tag co-occurrence statistics from the current library.
Reads ID3 tags from tracks in the embedding cache, computes base rates
and conditional probabilities, saves as JSON for Swift to load.
"""
import json, os, sys
from collections import defaultdict, Counter
from pathlib import Path
from mutagen.id3 import ID3
from mutagen.mp3 import MP3

def read_tags(path):
    """Read ID3 tags using the same fields as TrainingDataCollector."""
    try:
        audio = MP3(path, ID3=ID3)
        if audio.tags is None:
            return set()
        tags = set()
        # Genre (TCON)
        if 'TCON' in audio.tags:
            for v in audio.tags['TCON'].text:
                tags.update(t.strip() for t in str(v).split(',') if t.strip())
        # Timing (TALB - album field)
        if 'TALB' in audio.tags:
            for v in audio.tags['TALB'].text:
                if str(v).strip(): tags.add(str(v).strip())
        # Mood (TIT1 - content group)
        if 'TIT1' in audio.tags:
            for v in audio.tags['TIT1'].text:
                if str(v).strip(): tags.add(str(v).strip())
        # Descriptive (COMM)
        for k in audio.tags.keys():
            if k.startswith('COMM'):
                for v in audio.tags[k].text:
                    tags.update(t.strip() for t in str(v).split(',') if t.strip())
        # Normalize to title case (match TagNormalizer)
        normalized = set()
        for t in tags:
            parts = [p.strip() for p in t.split('/')]
            nps = []
            for p in parts:
                words = p.split()
                nps.append(' '.join(w[0].upper() + w[1:].lower() if w else w for w in words))
            normalized.add('/'.join(nps))
        return normalized
    except Exception:
        return set()

def main():
    app_support = Path.home() / "Library/Application Support/CrateBot"
    cache_path = app_support / "embedding_cache.json"
    models_dir = app_support / "Models"

    # Find latest model to get known tags
    model_dirs = sorted(
        [d for d in models_dir.iterdir() if d.is_dir()],
        key=lambda d: d.stat().st_mtime, reverse=True
    )
    if not model_dirs:
        print("No trained models found"); return

    with open(model_dirs[0] / f"{model_dirs[0].name}.json") as f:
        meta = json.load(f)
    known = set()
    for tags in meta['tags'].values():
        known.update(tags)

    # Read ID3 tags from every track in the cache
    with open(cache_path) as f:
        cache = json.load(f)

    print(f"Reading ID3 tags from {len(cache)} tracks...")
    track_tags = []
    for path in cache:
        if os.path.exists(path):
            t = read_tags(path) & known
            if t:
                track_tags.append(t)

    N = len(track_tags)
    print(f"Analyzed {N} tracks with at least one known tag")

    # Compute stats
    single = Counter()
    for t in track_tags:
        for tag in t:
            single[tag] += 1

    co = defaultdict(lambda: defaultdict(int))
    for t in track_tags:
        tl = list(t)
        for i in range(len(tl)):
            for j in range(len(tl)):
                if i != j:
                    co[tl[i]][tl[j]] += 1

    # Build output
    stats = {
        'version': 1,
        'total_tracks': N,
        'base_rates': {tag: round(count / N, 4) for tag, count in single.items()},
        'conditional': {}
    }

    MIN_SUPPORT = 10
    LIFT_THRESHOLD_HIGH = 1.5
    LIFT_THRESHOLD_LOW = 0.5

    for a in single:
        if single[a] < MIN_SUPPORT:
            continue
        conditionals = {}
        p_a = single[a] / N
        for b in co[a]:
            if single[b] < MIN_SUPPORT:
                continue
            p_b_given_a = co[a][b] / single[a]
            p_b = single[b] / N
            lift = p_b_given_a / p_b if p_b > 0 else 0
            if lift >= LIFT_THRESHOLD_HIGH or lift <= LIFT_THRESHOLD_LOW:
                conditionals[b] = round(p_b_given_a, 4)
        if conditionals:
            stats['conditional'][a] = conditionals

    output_path = Path("CrateBotCore/Sources/CrateBotCore/Resources/tag_cooccurrence.json")
    with open(output_path, 'w') as f:
        json.dump(stats, f, indent=2, sort_keys=True)

    total_cond = sum(len(v) for v in stats['conditional'].values())
    print(f"Saved {len(stats['base_rates'])} base rates and {total_cond} conditional probabilities")
    print(f"Output: {output_path}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it**

```bash
python3 scripts/generate_tag_cooccurrence.py
```

Expected: `CrateBotCore/Sources/CrateBotCore/Resources/tag_cooccurrence.json` created with ~47 base rates and ~500 conditional pairs.

- [ ] **Step 3: Add to Package.swift resources**

In `CrateBotCore/Package.swift`, add to the resources array:
```swift
.copy("Resources/tag_cooccurrence.json"),
```

- [ ] **Step 4: Commit**

```bash
git add scripts/generate_tag_cooccurrence.py CrateBotCore/Sources/CrateBotCore/Resources/tag_cooccurrence.json CrateBotCore/Package.swift
git commit -m "feat: add tag co-occurrence statistics for post-hoc boosting"
```

---

## Chunk 2: TagCooccurrenceBooster Core

### Task 2: Create the booster struct with tests

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/TagCooccurrenceBooster.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/TagCooccurrenceBoosterTests.swift`

- [ ] **Step 1: Write failing tests**

Create `CrateBotCore/Tests/CrateBotCoreTests/ML/TagCooccurrenceBoosterTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class TagCooccurrenceBoosterTests: XCTestCase {

    // Synthetic stats for testing: 100 tracks, House is 50%, Driving is 40%,
    // P(Driving | House) = 0.9 (strong positive lift), P(Techno | House) = 0.05 (negative)
    private func makeBooster() -> TagCooccurrenceBooster {
        let stats = TagCooccurrenceBooster.Stats(
            totalTracks: 100,
            baseRates: ["House": 0.5, "Driving": 0.4, "Techno": 0.1, "Happy": 0.3, "Aggressive": 0.2],
            conditional: [
                "House": ["Driving": 0.9, "Techno": 0.05],
                "Aggressive": ["Happy": 0.02]
            ]
        )
        return TagCooccurrenceBooster(stats: stats, boostWeight: 0.5, confidentThreshold: 0.8)
    }

    func testNoConfidentTagsNoChange() {
        let booster = makeBooster()
        // All raw probabilities below threshold — no boosting
        let raw: [String: Float] = ["House": 0.5, "Driving": 0.4, "Techno": 0.1]
        let adjusted = booster.adjust(probabilities: raw)
        for (tag, p) in raw {
            XCTAssertEqual(adjusted[tag] ?? 0, p, accuracy: 0.001, "Tag \(tag) should be unchanged")
        }
    }

    func testConfidentTagBoostsCorrelatedTag() {
        let booster = makeBooster()
        // House is highly confident — Driving should be boosted (lift = 0.9/0.4 = 2.25)
        let raw: [String: Float] = ["House": 0.95, "Driving": 0.5, "Techno": 0.2]
        let adjusted = booster.adjust(probabilities: raw)
        XCTAssertGreaterThan(adjusted["Driving"] ?? 0, 0.5, "Driving should be boosted")
        XCTAssertLessThan(adjusted["Techno"] ?? 1, 0.2, "Techno should be penalized (negative lift)")
    }

    func testConfidentTagIsNotSelfBoosted() {
        let booster = makeBooster()
        let raw: [String: Float] = ["House": 0.95, "Driving": 0.5]
        let adjusted = booster.adjust(probabilities: raw)
        // House itself should not be modified based on its own confidence
        XCTAssertEqual(adjusted["House"] ?? 0, 0.95, accuracy: 0.01)
    }

    func testMutuallyExclusiveTagsPenalize() {
        let booster = makeBooster()
        // Aggressive is confident, Happy has a strong negative lift (0.02 / 0.3 = 0.067)
        let raw: [String: Float] = ["Aggressive": 0.9, "Happy": 0.6]
        let adjusted = booster.adjust(probabilities: raw)
        XCTAssertLessThan(adjusted["Happy"] ?? 1, 0.6, "Happy should be penalized")
    }

    func testAdjustmentIsClampedToValidRange() {
        let booster = makeBooster()
        let raw: [String: Float] = ["House": 0.99, "Driving": 0.99]
        let adjusted = booster.adjust(probabilities: raw)
        for (_, p) in adjusted {
            XCTAssertGreaterThanOrEqual(p, 0.0)
            XCTAssertLessThanOrEqual(p, 1.0)
        }
    }

    func testMissingStatsForTagLeavesUnchanged() {
        let booster = makeBooster()
        // "Mystery" is not in stats — should pass through unchanged
        let raw: [String: Float] = ["House": 0.95, "Mystery": 0.6]
        let adjusted = booster.adjust(probabilities: raw)
        XCTAssertEqual(adjusted["Mystery"] ?? 0, 0.6, accuracy: 0.001)
    }

    func testLoadFromBundleSucceeds() {
        let booster = TagCooccurrenceBooster.loadFromBundle()
        XCTAssertNotNil(booster, "Booster should load from bundled resource")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd CrateBotCore && swift test --filter TagCooccurrenceBoosterTests
```
Expected: FAIL — `TagCooccurrenceBooster` doesn't exist yet.

- [ ] **Step 3: Implement TagCooccurrenceBooster**

Create `CrateBotCore/Sources/CrateBotCore/ML/TagCooccurrenceBooster.swift`:

```swift
import Foundation
import os.log

/// Post-hoc boosting of binary classifier outputs using tag co-occurrence statistics.
///
/// Binary classifiers predict each tag independently, throwing away information about
/// which tags tend to appear together. This booster corrects for that by adjusting
/// each tag's probability based on confident predictions of correlated tags.
///
/// For each tag A with raw probability P(A), and for each "confident" tag B
/// (raw probability ≥ `confidentThreshold`), we adjust P(A) in logit space
/// proportional to the log-lift log(P(A|B) / P(A)). Positive lifts boost, negative
/// lifts penalize. The total adjustment is weighted by `boostWeight`.
public struct TagCooccurrenceBooster: Sendable {

    /// Co-occurrence statistics loaded from bundled JSON.
    public struct Stats: Codable, Sendable {
        public let totalTracks: Int
        public let baseRates: [String: Float]
        public let conditional: [String: [String: Float]]

        private enum CodingKeys: String, CodingKey {
            case totalTracks = "total_tracks"
            case baseRates = "base_rates"
            case conditional
        }

        public init(totalTracks: Int, baseRates: [String: Float], conditional: [String: [String: Float]]) {
            self.totalTracks = totalTracks
            self.baseRates = baseRates
            self.conditional = conditional
        }
    }

    private let stats: Stats
    private let boostWeight: Float
    private let confidentThreshold: Float
    private let logger = Logger(subsystem: "com.cratebot", category: "TagCooccurrenceBooster")

    /// - Parameters:
    ///   - stats: Co-occurrence statistics.
    ///   - boostWeight: How much weight to give the co-occurrence signal vs raw classifier.
    ///     0.0 = no boosting (identity), 1.0 = full Bayes-style adjustment. Default 0.5.
    ///   - confidentThreshold: A tag is treated as a boosting signal only when its raw
    ///     probability meets this threshold. Default 0.8.
    public init(stats: Stats, boostWeight: Float = 0.5, confidentThreshold: Float = 0.8) {
        self.stats = stats
        self.boostWeight = boostWeight
        self.confidentThreshold = confidentThreshold
    }

    /// Load from bundled `tag_cooccurrence.json` resource.
    public static func loadFromBundle(
        boostWeight: Float = 0.5,
        confidentThreshold: Float = 0.8
    ) -> TagCooccurrenceBooster? {
        guard let url = Bundle.module.url(forResource: "tag_cooccurrence", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode(Stats.self, from: data) else {
            return nil
        }
        return TagCooccurrenceBooster(
            stats: stats,
            boostWeight: boostWeight,
            confidentThreshold: confidentThreshold
        )
    }

    /// Adjust raw tag probabilities using co-occurrence statistics.
    ///
    /// The adjustment happens in logit space:
    ///   adjusted_logit(A) = logit(A) + boostWeight · Σ_B log(P(A|B) / P(A))
    /// where the sum is over confident tags B != A that have a conditional probability stored.
    ///
    /// - Parameter probabilities: Raw probabilities per tag from the binary classifiers.
    /// - Returns: Adjusted probabilities, same keys.
    public func adjust(probabilities: [String: Float]) -> [String: Float] {
        // Identify confident tags
        let confidentTags = probabilities.filter { $0.value >= confidentThreshold }.map { $0.key }
        guard !confidentTags.isEmpty else { return probabilities }

        var adjusted: [String: Float] = [:]
        for (tag, p) in probabilities {
            // Don't boost a tag based on its own confidence
            var logLiftSum: Float = 0
            for confidentTag in confidentTags where confidentTag != tag {
                // Look up P(tag | confidentTag)
                if let pBGivenA = stats.conditional[confidentTag]?[tag],
                   let pB = stats.baseRates[tag], pB > 0 {
                    let lift = pBGivenA / pB
                    if lift > 0 {
                        logLiftSum += Float(log(Double(lift)))
                    }
                }
            }

            if logLiftSum == 0 {
                adjusted[tag] = p
            } else {
                let logitP = Self.logit(clamp(p))
                let adjustedLogit = logitP + boostWeight * logLiftSum
                adjusted[tag] = Self.sigmoid(adjustedLogit)
            }
        }

        return adjusted
    }

    // MARK: - Math helpers

    private static let epsilon: Float = 1e-6

    private func clamp(_ p: Float) -> Float {
        return max(Self.epsilon, min(1 - Self.epsilon, p))
    }

    private static func logit(_ p: Float) -> Float {
        return log(p / (1 - p))
    }

    private static func sigmoid(_ x: Float) -> Float {
        return 1 / (1 + exp(-x))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd CrateBotCore && swift test --filter TagCooccurrenceBoosterTests
```
Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TagCooccurrenceBooster.swift CrateBotCore/Tests/CrateBotCoreTests/ML/TagCooccurrenceBoosterTests.swift
git commit -m "feat: add TagCooccurrenceBooster for post-hoc score adjustment"
```

---

## Chunk 3: Integrate into TaggingEngine

### Task 3: Apply booster in TaggingEngine inference

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

- [ ] **Step 1: Add booster property and init**

After the `zeroShotMatcher` property, add:

```swift
/// Tag co-occurrence booster for post-hoc score adjustment
private let cooccurrenceBooster: TagCooccurrenceBooster?

/// Whether to apply co-occurrence boosting (set externally for A/B testing)
public var useCooccurrenceBoosting: Bool = true
```

In `init()`, after loading `zeroShotMatcher`:

```swift
self.cooccurrenceBooster = TagCooccurrenceBooster.loadFromBundle()
if cooccurrenceBooster != nil {
    logger.info("Loaded tag co-occurrence booster")
}
```

- [ ] **Step 2: Apply booster in the classifier loop**

The current pattern in `analyze()` is:
```swift
for classifier in userClassifiers {
    let (_, rawConfidence) = try classifier.predictWithConfidence(...)
    let confidence = confidenceCalibrator.calibrate(rawConfidence)
    let effectiveThreshold = tagThresholds?[classifier.tagName] ?? classificationThreshold
    if confidence >= effectiveThreshold {
        predictedTags.append(classifier.tagName)
    }
    ...
}
```

Change this to a two-pass approach:

```swift
// Pass 1: collect raw probabilities for all classifiers
var rawProbabilities: [String: Float] = [:]
for classifier in userClassifiers {
    trainedTagNames.insert(classifier.tagName.lowercased())
    do {
        let (_, rawConfidence) = try classifier.predictWithConfidence(features: extendedFeatures)
        let calibrated = confidenceCalibrator.calibrate(rawConfidence)
        rawProbabilities[classifier.tagName] = calibrated
    } catch {
        logger.error("Classifier '\(classifier.tagName)' failed: \(error.localizedDescription)")
    }
}

// Pass 2: apply co-occurrence boosting if enabled
let adjustedProbabilities: [String: Float]
if useCooccurrenceBoosting, let booster = cooccurrenceBooster {
    adjustedProbabilities = booster.adjust(probabilities: rawProbabilities)
} else {
    adjustedProbabilities = rawProbabilities
}

// Pass 3: threshold and apply tags
for (tagName, confidence) in adjustedProbabilities {
    let effectiveThreshold = tagThresholds?[tagName] ?? classificationThreshold
    if confidence >= effectiveThreshold {
        predictedTags.append(tagName)
    } else if rawProbabilities[tagName, default: 0] > 0 {
        // Below threshold but non-zero - try hybrid Essentia fallback (uses raw, not boosted)
        let shouldApply = checkHybridEssentiaFallback(
            tagName: tagName,
            userConfidence: rawProbabilities[tagName, default: 0],
            moodPredictions: moodPredictions,
            genrePredictions: genrePredictions,
            instrumentPredictions: instrumentPredictions
        )
        if shouldApply {
            predictedTags.append(tagName)
        }
    }
}
```

Note: The `checkHybridEssentiaFallback` continues to use the **raw** (pre-boost) confidence to maintain the original fallback semantics.

- [ ] **Step 3: Run all tests**

```bash
cd CrateBotCore && swift test
```
Expected: All 369+ tests PASS.

- [ ] **Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift
git commit -m "feat: integrate co-occurrence booster into TaggingEngine

Binary classifiers now run first to collect raw probabilities, then
TagCooccurrenceBooster adjusts them using tag correlation statistics,
then thresholds are applied. Enabled by default, can be disabled via
useCooccurrenceBoosting flag for A/B testing."
```

---

## Chunk 4: Evaluate the Boost

### Task 4: Add --boost flag to accuracy_eval.py

**Files:**
- Modify: `scripts/accuracy_eval.py`

- [ ] **Step 1: Replicate the booster logic in Python**

Add a Python implementation of the same boosting math, so `accuracy_eval.py` can compare boosted vs unboosted without needing to rebuild the Swift app.

After the inference loop in `load_data_and_run_inference`, add a new function:

```python
def apply_cooccurrence_boost(raw_probs, stats, boost_weight=0.5, confident_threshold=0.8):
    """Apply post-hoc co-occurrence boosting to a list of raw probability dicts."""
    import math

    base_rates = stats['base_rates']
    conditional = stats['conditional']
    boosted = []

    for probs in raw_probs:
        confident = [t for t, p in probs.items() if p >= confident_threshold]
        adjusted = {}
        for tag, p in probs.items():
            log_lift = 0.0
            for c in confident:
                if c == tag: continue
                p_b_given_a = conditional.get(c, {}).get(tag)
                p_b = base_rates.get(tag)
                if p_b_given_a and p_b and p_b > 0:
                    lift = p_b_given_a / p_b
                    if lift > 0:
                        log_lift += math.log(lift)
            if log_lift == 0:
                adjusted[tag] = p
            else:
                # Clamp and convert to logit
                eps = 1e-6
                p_clamped = max(eps, min(1 - eps, p))
                logit_p = math.log(p_clamped / (1 - p_clamped))
                adjusted_logit = logit_p + boost_weight * log_lift
                adjusted[tag] = 1 / (1 + math.exp(-adjusted_logit))
        boosted.append(adjusted)
    return boosted
```

In `main()`, load the stats and optionally apply boosting before `threshold_sweep` and `optimize_thresholds`:

```python
if '--boost' in sys.argv:
    stats_path = Path("CrateBotCore/Sources/CrateBotCore/Resources/tag_cooccurrence.json")
    if stats_path.exists():
        with open(stats_path) as f:
            stats = json.load(f)
        print(f"\nApplying co-occurrence boost...")
        data['raw_probs'] = apply_cooccurrence_boost(data['raw_probs'], stats)
        print(f"Boosted {len(data['raw_probs'])} probability dicts\n")
    else:
        print("Warning: tag_cooccurrence.json not found, running without boost")
```

- [ ] **Step 2: Run unboosted baseline**

```bash
python3 scripts/accuracy_eval.py > /tmp/eval_baseline.txt
```

- [ ] **Step 3: Run with boosting**

```bash
python3 scripts/accuracy_eval.py --boost > /tmp/eval_boosted.txt
```

- [ ] **Step 4: Compare macro F1**

```bash
grep -E "Best macro F1|Optimized macro F1" /tmp/eval_baseline.txt /tmp/eval_boosted.txt
```

Expected: Boosted macro F1 should be higher than baseline by 3-10%.

- [ ] **Step 5: Run optimizer with boosting**

```bash
python3 scripts/accuracy_eval.py --optimize --boost
```

This generates new per-tag thresholds calibrated against boosted probabilities.

- [ ] **Step 6: Commit**

```bash
git add scripts/accuracy_eval.py
git commit -m "feat: add --boost flag to accuracy_eval for co-occurrence evaluation"
```

---

## Chunk 5: Final Verification

### Task 5: End-to-end check

- [ ] **Step 1: Full test suite**

```bash
cd CrateBotCore && swift test 2>&1 | grep "Executed.*tests"
```
Expected: 375+ tests, 0 failures (7 new booster tests + 368 existing).

- [ ] **Step 2: Xcode build**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
xcodebuild -project CrateBot.xcodeproj -scheme CrateBot build 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Push all commits**

```bash
git push
```

---

## Summary

| Component | Lines | Risk |
|-----------|-------|------|
| tag_cooccurrence.json | ~500 entries | None — static data |
| generate_tag_cooccurrence.py | ~120 | None — script only |
| TagCooccurrenceBooster.swift | ~130 | Low — pure math, well-tested |
| TagCooccurrenceBoosterTests.swift | ~90 | None — tests |
| TaggingEngine.swift | ~40 changed | Low — additive with flag |
| accuracy_eval.py | ~40 added | None — script only |

Total new code: ~420 lines. Total modified code: ~40 lines. Zero retraining required. Fully reversible via the `useCooccurrenceBoosting` flag.

## Expected Outcome

Based on the 218 strong positive co-occurrences and 45 mutual exclusions in the current data:
- Macro F1 improvement: **5-10%** (from 28% baseline to 33-38%)
- Biggest wins on tags with high correlation to House (the hub)
- Smaller effects on independent tags like Acapella
- Mutual exclusion corrections may eliminate some false positives
