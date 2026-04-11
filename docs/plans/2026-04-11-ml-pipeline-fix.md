# ML Pipeline Fix Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the ML tagging pipeline so trained classifiers produce accurate, reliable tag predictions instead of the current broken output.

**Architecture:** Seven targeted fixes across the training and inference pipeline. Each fix addresses a specific root cause identified by three independent analyses (internal root cause, fresheyes/gpt-5.2-codex review, and manual code verification). No architectural rewrites — parameter changes, bug fixes, and removal of broken heuristics.

**Tech Stack:** Swift, CoreML, CreateML (BoostedTreeClassifier), SwiftUI

---

## Root Cause Summary

The tagging pipeline has these compounding failures:

1. **ConfidenceCalibrator applies sigmoid to already-bounded probabilities** — BoostedTree outputs [0,1], sigmoid compresses toward 0.5, making thresholds unreliable
2. **3:1 negative ratio biases classifiers against tagging** — models learn "say no" is right 75% of the time
3. **fuzzyMatch in hybrid fallback creates false positives** — `"house".contains("house")` matches "Ambient relaxing House music"
4. **Tags not case-normalized** — "House", "house", "HOUSE" split training samples into separate tags
5. **Augmented features cached permanently** — noise baked into cache, not regenerated per training run
6. **AnthropicClient loses error messages** — catch block re-throws with empty string
7. **Threshold slider in AddFallbackMappingSheet does nothing** — maps to deprecated field

Z-score normalization was previously tried and removed (ModelTrainer.swift:428-434) because it caused train/inference distribution mismatch. We will NOT re-add it.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `CrateBotCore/Sources/CrateBotCore/ML/ConfidenceCalibrator.swift` | Modify | Fix calibrate() to use linear scaling instead of sigmoid |
| `CrateBotCore/Sources/CrateBotCore/ML/TrainingConfiguration.swift` | Modify | Change maxNegativeRatio default from 3.0 to 1.5 |
| `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift` | Modify | Change TrainingConfig maxNegativeRatio default from 3.0 to 1.5 |
| `CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift` | Modify | Change maxNegativeRatio default from 3.0 to 1.5 |
| `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` | Modify | Remove fuzzyMatch, require explicit mappings only |
| `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift` | Modify | Normalize tags to canonical case; cache raw features not augmented |
| `CrateBotCore/Sources/CrateBotCore/ML/EmbeddingCache.swift` | No change | Cache is fine — augmentation moves out of the cached path |
| `CrateBotCore/Sources/CrateBotCore/Networking/AnthropicClient.swift` | Modify | Fix error message preservation in catch block |
| `CrateBot/Views/AddFallbackMappingSheet.swift` | Modify | Remove dead threshold slider |
| `CrateBotCore/Sources/CrateBotCore/Data/FeatureCompression.swift` | Modify | Store original byte count for safe decompression |
| `CrateBotCore/Tests/CrateBotCoreTests/ML/ConfidenceCalibratorTests.swift` | Create | Test new calibration behavior |
| `CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineFuzzyMatchTests.swift` | Create | Test that fuzzy matching is removed |
| `CrateBotCore/Tests/CrateBotCoreTests/ML/TagNormalizationTests.swift` | Create | Test case normalization in training data |
| `CrateBotCore/Tests/CrateBotCoreTests/FeatureCompressionTests.swift` | Modify | Add high-compression-ratio test |
| `CrateBotCore/Tests/CrateBotCoreTests/Networking/AnthropicClientTests.swift` | Modify | Add error message preservation test |

---

## Chunk 1: Fix Confidence Calibration

### Task 1: Fix ConfidenceCalibrator — remove sigmoid on bounded values

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ConfidenceCalibrator.swift:18-29`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/ConfidenceCalibratorTests.swift`

**Context:** BoostedTreeClassifier already outputs probabilities in [0,1]. The current `calibrate()` applies `sigmoid(rawConfidence / temperature)` which double-transforms the output, compressing predictions toward 0.5 and making threshold decisions unreliable. The fix: use linear temperature scaling that preserves the probability space.

- [ ] **Step 1: Write failing tests for new calibration behavior**

Create `CrateBotCore/Tests/CrateBotCoreTests/ML/ConfidenceCalibratorTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class ConfidenceCalibratorTests: XCTestCase {

    func testCalibrateWithDefaultTemperatureIsIdentity() {
        // Temperature 1.0 should pass through unchanged (minus smoothing)
        let calibrator = ConfidenceCalibrator(temperature: 1.0, smoothingFactor: 0.0)
        let result = calibrator.calibrate(0.75)
        XCTAssertEqual(result, 0.75, accuracy: 0.001)
    }

    func testCalibratePreservesOrdering() {
        let calibrator = ConfidenceCalibrator(temperature: 1.5, smoothingFactor: 0.1)
        let low = calibrator.calibrate(0.3)
        let mid = calibrator.calibrate(0.5)
        let high = calibrator.calibrate(0.8)
        XCTAssertLessThan(low, mid)
        XCTAssertLessThan(mid, high)
    }

    func testCalibrateHighTemperatureCompresses() {
        // High temperature should compress toward 0.5
        let calibrator = ConfidenceCalibrator(temperature: 2.0, smoothingFactor: 0.0)
        let result = calibrator.calibrate(0.9)
        XCTAssertLessThan(result, 0.9)
        XCTAssertGreaterThan(result, 0.5)
    }

    func testCalibrateLowTemperatureSharpens() {
        // Low temperature should sharpen (push away from 0.5)
        let calibrator = ConfidenceCalibrator(temperature: 0.5, smoothingFactor: 0.0)
        let result = calibrator.calibrate(0.7)
        XCTAssertGreaterThan(result, 0.7)
    }

    func testCalibrateClampsToBounds() {
        let calibrator = ConfidenceCalibrator(temperature: 0.3, smoothingFactor: 0.0)
        let high = calibrator.calibrate(1.0)
        let low = calibrator.calibrate(0.0)
        XCTAssertLessThanOrEqual(high, 1.0)
        XCTAssertGreaterThanOrEqual(low, 0.0)
    }

    func testCalibrateSmoothingReducesExtreme() {
        let calibrator = ConfidenceCalibrator(temperature: 1.0, smoothingFactor: 0.1)
        let result = calibrator.calibrate(1.0)
        // With smoothing 0.1: result * 0.9 + 0.05, so max is 0.95
        XCTAssertLessThanOrEqual(result, 0.95 + 0.001)
    }

    func testFitProducesReasonableTemperature() {
        var calibrator = ConfidenceCalibrator()
        // Well-calibrated predictions should produce temperature near 1.0
        let predictions: [Float] = [0.9, 0.8, 0.7, 0.2, 0.1, 0.15]
        let labels: [Bool] = [true, true, true, false, false, false]
        calibrator.fit(predictions: predictions, labels: labels)
        XCTAssertGreaterThan(calibrator.temperature, 0.3)
        XCTAssertLessThan(calibrator.temperature, 5.0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CrateBotCore && swift test --filter ConfidenceCalibratorTests 2>&1 | tail -20`
Expected: FAIL — `testCalibrateWithDefaultTemperatureIsIdentity` will fail because current sigmoid-based calibrate(0.75) returns ~0.629, not 0.75.

- [ ] **Step 3: Fix the calibrate() method**

In `CrateBotCore/Sources/CrateBotCore/ML/ConfidenceCalibrator.swift`, replace lines 17-29:

**Current code:**
```swift
/// Calibrate a raw confidence score
public func calibrate(_ rawConfidence: Float) -> Float {
    // Apply temperature scaling
    let scaled = rawConfidence / temperature

    // Apply sigmoid to get calibrated probability
    let calibrated = 1.0 / (1.0 + exp(-scaled))

    // Adjust for label smoothing (reduce overconfidence)
    let adjusted = calibrated * (1.0 - smoothingFactor) + smoothingFactor / 2.0

    return adjusted
}
```

**New code:**
```swift
/// Calibrate a raw confidence score using linear temperature scaling.
/// BoostedTree outputs are already probabilities in [0,1], so we scale
/// around the midpoint (0.5) rather than applying sigmoid which would
/// double-transform the output and compress predictions toward 0.5.
public func calibrate(_ rawConfidence: Float) -> Float {
    // Linear scaling around 0.5: higher temperature compresses toward 0.5,
    // lower temperature sharpens away from 0.5
    let centered = rawConfidence - 0.5
    let scaled = centered / temperature
    let calibrated = min(max(scaled + 0.5, 0.0), 1.0)

    // Adjust for label smoothing (reduce overconfidence)
    let adjusted = calibrated * (1.0 - smoothingFactor) + smoothingFactor / 2.0

    return adjusted
}
```

Also update the `fit()` method (lines 32-62) to use the new linear calibration in its loss computation:

**Current code (line 48):**
```swift
let calibrated = 1.0 / (1.0 + exp(-scaled))
```

**New code:**
```swift
let centered = pred - 0.5
let scaledVal = centered / temp
let calibrated = min(max(scaledVal + 0.5, 0.0), 1.0)
```

And change the grid search range to match the new scaling behavior:

**Current (line 42):**
```swift
for t in stride(from: 0.5, through: 3.0, by: 0.1) {
```

**New:**
```swift
for t in stride(from: 0.3, through: 5.0, by: 0.1) {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CrateBotCore && swift test --filter ConfidenceCalibratorTests 2>&1 | tail -20`
Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd CrateBotCore && git add Sources/CrateBotCore/ML/ConfidenceCalibrator.swift Tests/CrateBotCoreTests/ML/ConfidenceCalibratorTests.swift
git commit -m "fix: replace sigmoid calibration with linear temperature scaling

BoostedTree outputs are already probabilities in [0,1]. Applying sigmoid
double-transforms the output and compresses predictions toward 0.5,
making threshold decisions unreliable. Linear scaling around the midpoint
preserves the probability space while still allowing temperature-based
calibration.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 2: Fix Class Imbalance

### Task 2: Change maxNegativeRatio default from 3.0 to 1.5

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingConfiguration.swift:52`
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift:51`
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift:30`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingConfigurationTests.swift`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelTrainerTests.swift`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/BinaryTrainingDataGeneratorTests.swift`

**Context:** With 3:1 ratio, a tag with 50 positives trains on 150 negatives. BoostedTrees without class weighting learn a bias toward negative predictions. Ratio 1.5 keeps some diversity in negative examples while reducing the class imbalance to a manageable level.

- [ ] **Step 1: Update defaults in all three files**

In `TrainingConfiguration.swift` line 52, change:
```swift
maxNegativeRatio: Double = 3.0,
```
to:
```swift
maxNegativeRatio: Double = 1.5,
```

In `ModelTrainer.swift` line 51, change:
```swift
maxNegativeRatio: Double = 3.0,
```
to:
```swift
maxNegativeRatio: Double = 1.5,
```

In `BinaryTrainingDataGenerator.swift` line 30, change:
```swift
public init(minPositiveExamples: Int = 50, maxNegativeRatio: Double = 3.0) {
```
to:
```swift
public init(minPositiveExamples: Int = 50, maxNegativeRatio: Double = 1.5) {
```

- [ ] **Step 2: Update test assertions**

In `TrainingConfigurationTests.swift`, update the default value assertion:
```swift
XCTAssertEqual(config.maxNegativeRatio, 1.5)
```

In `ModelTrainerTests.swift`, update the default value assertion:
```swift
XCTAssertEqual(config.maxNegativeRatio, 1.5, accuracy: 0.001)
```

In `BinaryTrainingDataGeneratorTests.swift`, update:
```swift
XCTAssertEqual(generator.maxNegativeRatio, 1.5)
```

- [ ] **Step 3: Run all affected tests**

Run: `cd CrateBotCore && swift test --filter "TrainingConfigurationTests|ModelTrainerTests|BinaryTrainingDataGeneratorTests" 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
cd CrateBotCore && git add Sources/CrateBotCore/ML/TrainingConfiguration.swift Sources/CrateBotCore/ML/ModelTrainer.swift Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift Tests/
git commit -m "fix: reduce maxNegativeRatio from 3.0 to 1.5 to fix class imbalance

3:1 ratio biases BoostedTree classifiers toward negative predictions
because they learn 'say no' is correct 75% of the time. 1.5:1 maintains
negative diversity while reducing the imbalance to a level where the
classifier can learn meaningful positive signal.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 3: Remove Fuzzy Match from Hybrid Fallback

### Task 3: Remove fuzzyMatch — require explicit fallback mappings only

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:727-799`

**Context:** The `fuzzyMatch()` function uses `String.contains()` which produces false positives (e.g., "house" matches "Ambient---relaxing House music"). The explicit fallback mapping system (lines 712-725) already handles tag-to-Essentia mapping correctly. Removing fuzzy matching eliminates unpredictable tag application while keeping the explicit mapping path intact.

- [ ] **Step 1: Modify findBestEssentiaMatch to remove fuzzy matching**

In `TaggingEngine.swift`, replace lines 727-751 (the fuzzy matching fallback in `findBestEssentiaMatch`) with a simple return:

**Current code (lines 726-751):**
```swift
        // Otherwise, try fuzzy matching against Essentia labels
        var bestMatch: Float = 0

        // Check moods
        for (label, confidence) in moodPredictions {
            if fuzzyMatch(normalizedTag, label.lowercased()) {
                bestMatch = max(bestMatch, confidence)
            }
        }

        // Check genres
        for (label, confidence) in genrePredictions {
            if fuzzyMatch(normalizedTag, label.lowercased()) {
                bestMatch = max(bestMatch, confidence)
            }
        }

        // Check instruments
        for (label, confidence) in instrumentPredictions {
            if fuzzyMatch(normalizedTag, label.lowercased()) {
                bestMatch = max(bestMatch, confidence)
            }
        }

        return bestMatch
```

**New code:**
```swift
        // No explicit mapping found — return 0 (no fuzzy matching)
        // Fuzzy string matching was removed because String.contains() produced
        // false positives (e.g., "house" matching "Ambient relaxing House music").
        // Use the Fallback Mappings editor to create explicit tag-to-Essentia mappings.
        return 0
```

- [ ] **Step 2: Remove the fuzzyMatch method entirely**

Delete lines 754-799 (the entire `fuzzyMatch` private method).

- [ ] **Step 3: Run existing TaggingEngine tests**

Run: `cd CrateBotCore && swift test --filter TaggingEngineTests 2>&1 | tail -20`
Expected: All PASS (fuzzyMatch was not tested).

- [ ] **Step 4: Commit**

```bash
cd CrateBotCore && git add Sources/CrateBotCore/ML/TaggingEngine.swift
git commit -m "fix: remove fuzzy string matching from hybrid Essentia fallback

String.contains() matching produced false positives — 'house' matched
'Ambient relaxing House music', 'dark' matched any label containing
'dark'. Explicit fallback mappings (configurable in the UI) remain
the only path for Essentia-boosted predictions.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 4: Normalize Tags to Canonical Case

### Task 4: Case-normalize tags during training data collection

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift:950-977`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/TagNormalizationTests.swift`

**Context:** Tags from ID3 are not case-normalized. "House", "house", and "HOUSE" are treated as separate tags, splitting positive samples and reducing effective training set size per tag. The fix: normalize to title case (capitalize first letter of each word) during `convertToTagSet()`, matching the typical DJ tagging convention.

- [ ] **Step 1: Write failing tests for tag normalization**

Create `CrateBotCore/Tests/CrateBotCoreTests/ML/TagNormalizationTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class TagNormalizationTests: XCTestCase {

    func testNormalizeTagTitleCases() {
        XCTAssertEqual(TagNormalizer.normalize("house"), "House")
        XCTAssertEqual(TagNormalizer.normalize("HOUSE"), "House")
        XCTAssertEqual(TagNormalizer.normalize("House"), "House")
    }

    func testNormalizeTagPreservesMultiWord() {
        XCTAssertEqual(TagNormalizer.normalize("deep house"), "Deep House")
        XCTAssertEqual(TagNormalizer.normalize("DEEP HOUSE"), "Deep House")
    }

    func testNormalizeTagTrimsWhitespace() {
        XCTAssertEqual(TagNormalizer.normalize("  house  "), "House")
        XCTAssertEqual(TagNormalizer.normalize("house\t"), "House")
    }

    func testNormalizeTagHandlesEmpty() {
        XCTAssertEqual(TagNormalizer.normalize(""), "")
        XCTAssertEqual(TagNormalizer.normalize("   "), "")
    }

    func testNormalizeTagHandlesSlashes() {
        XCTAssertEqual(TagNormalizer.normalize("dub/reggae"), "Dub/Reggae")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CrateBotCore && swift test --filter TagNormalizationTests 2>&1 | tail -20`
Expected: FAIL — `TagNormalizer` doesn't exist yet.

- [ ] **Step 3: Add TagNormalizer utility and apply in convertToTagSet**

Add to the top of `TrainingDataCollector.swift` (after the imports, before the actor):

```swift
/// Normalizes tag strings to canonical title case for consistent training.
/// "house", "HOUSE", "House" all become "House".
public enum TagNormalizer {
    public static func normalize(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Split on spaces and slashes, capitalize each word
        return trimmed
            .components(separatedBy: CharacterSet(charactersIn: " /"))
            .enumerated()
            .map { index, word in
                guard !word.isEmpty else { return word }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: trimmed.contains("/") && !trimmed.contains(" ") ? "/" : " ")
    }
}
```

Then update `convertToTagSet()` (lines 950-980) to normalize each tag before inserting:

Replace each `tagSet.insert(...)` call to use `TagNormalizer.normalize()`:

At line 955, change:
```swift
tagSet.insert(value.trimmingCharacters(in: .whitespaces))
```
to:
```swift
let normalized = TagNormalizer.normalize(value)
if !normalized.isEmpty { tagSet.insert(normalized) }
```

At line 960, change:
```swift
tagSet.insert(value.trimmingCharacters(in: .whitespaces))
```
to:
```swift
let normalizedTiming = TagNormalizer.normalize(value)
if !normalizedTiming.isEmpty { tagSet.insert(normalizedTiming) }
```

At line 965, change:
```swift
tagSet.insert(value.trimmingCharacters(in: .whitespaces))
```
to:
```swift
let normalizedMood = TagNormalizer.normalize(value)
if !normalizedMood.isEmpty { tagSet.insert(normalizedMood) }
```

At lines 971-976, change:
```swift
let individualTags = value.split(separator: ",").map {
    $0.trimmingCharacters(in: .whitespaces)
}
for tag in individualTags where !tag.isEmpty {
    tagSet.insert(tag)
}
```
to:
```swift
let individualTags = value.split(separator: ",").map {
    TagNormalizer.normalize(String($0))
}
for tag in individualTags where !tag.isEmpty {
    tagSet.insert(tag)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd CrateBotCore && swift test --filter TagNormalizationTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
cd CrateBotCore && git add Sources/CrateBotCore/ML/TrainingDataCollector.swift Tests/CrateBotCoreTests/ML/TagNormalizationTests.swift
git commit -m "fix: normalize tags to title case during training data collection

Tags from ID3 metadata are not case-consistent — 'House', 'house', and
'HOUSE' were treated as separate tags, splitting positive samples. All
tags are now normalized to title case (capitalize first letter of each
word) before insertion into the training set.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 5: Cache Raw Features, Not Augmented

### Task 5: Move augmentation out of the cached path

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift:803-809`

**Context:** Feature noise augmentation (line 804) is applied before caching (line 832). Subsequent training runs reuse the same noisy features from cache instead of generating fresh augmentation. The fix: cache the raw averaged features, then apply augmentation after cache retrieval. This also means cached features can be reused across different augmentation configs.

- [ ] **Step 1: Move augmentation after caching**

In `TrainingDataCollector.swift`, change lines 798-809:

**Current code:**
```swift
guard let averaged = Self.averageFeatures(segmentFeatures, expectedDimension: expectedDimension) else {
    Self.debugLog("Track \(fileURL.lastPathComponent) produced no valid segments - skipping")
    return (globalIndex, track, nil)
}

// Apply feature-level augmentation for training robustness
let augmentedFeatures = AudioAugmenter.augmentFeatures(
    averaged,
    addNoise: augConfig.featureNoiseEnabled,
    noiseScale: augConfig.featureNoiseScale
)
return (globalIndex, track, augmentedFeatures)
```

**New code:**
```swift
guard let averaged = Self.averageFeatures(segmentFeatures, expectedDimension: expectedDimension) else {
    Self.debugLog("Track \(fileURL.lastPathComponent) produced no valid segments - skipping")
    return (globalIndex, track, nil)
}

// Return raw features — augmentation is applied after caching
// so cached embeddings remain clean and reusable across configs
return (globalIndex, track, averaged)
```

Then in the results processing section (lines 824-837), apply augmentation after cache storage:

**Current code:**
```swift
for (_, track, features) in batchResults {
    if let features = features, !features.isEmpty {
        let updatedTrack = TaggedTrack(id: track.id, tags: track.tags, features: features)
        extractedTracks.append(updatedTrack)

        // Cache the embeddings
        let fileURL = URL(fileURLWithPath: track.id)
        await embeddingCache.set(features, for: fileURL)
    } else {
        // Failed to extract features - keep track without features
        extractedTracks.append(track)
    }
}
```

**New code:**
```swift
for (_, track, features) in batchResults {
    if let features = features, !features.isEmpty {
        // Cache raw (unaugmented) embeddings
        let fileURL = URL(fileURLWithPath: track.id)
        await embeddingCache.set(features, for: fileURL)

        // Apply augmentation AFTER caching for training robustness
        let augmentedFeatures = AudioAugmenter.augmentFeatures(
            features,
            addNoise: augConfig.featureNoiseEnabled,
            noiseScale: augConfig.featureNoiseScale
        )
        let updatedTrack = TaggedTrack(id: track.id, tags: track.tags, features: augmentedFeatures)
        extractedTracks.append(updatedTrack)
    } else {
        // Failed to extract features - keep track without features
        extractedTracks.append(track)
    }
}
```

Also apply augmentation to cached features (lines 710-722). Currently cached features are returned as-is:

**Current code:**
```swift
if let cachedFeatures = await embeddingCache.get(for: fileURL) {
    let updatedTrack = TaggedTrack(id: track.id, tags: track.tags, features: cachedFeatures)
    cachedTracks.append(updatedTrack)
```

**New code:**
```swift
if let cachedFeatures = await embeddingCache.get(for: fileURL) {
    // Apply augmentation to cached features (fresh noise each run)
    let augmentedCached = AudioAugmenter.augmentFeatures(
        cachedFeatures,
        addNoise: self.augmentationConfig.featureNoiseEnabled,
        noiseScale: self.augmentationConfig.featureNoiseScale
    )
    let updatedTrack = TaggedTrack(id: track.id, tags: track.tags, features: augmentedCached)
    cachedTracks.append(updatedTrack)
```

Note: Need to verify the property name for augmentation config on the actor. Search for `augmentationConfig` or `augConfig` as an instance property.

- [ ] **Step 2: Run existing tests**

Run: `cd CrateBotCore && swift test --filter TrainingDataCollectorTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 3: Commit**

```bash
cd CrateBotCore && git add Sources/CrateBotCore/ML/TrainingDataCollector.swift
git commit -m "fix: cache raw features, apply augmentation after cache retrieval

Feature noise was applied before caching, baking one noise sample
permanently into the cache. Now raw features are cached and augmentation
is applied fresh on each training run — both for newly extracted and
cached features. This makes augmentation actually effective and lets
cached features be reused across different augmentation configs.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 6: Fix AnthropicClient Error Message Loss

### Task 6: Preserve error messages in AnthropicClient catch block

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/Networking/AnthropicClient.swift:237-238`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/Networking/AnthropicClientTests.swift`

**Context:** Line 237 catches `AnthropicError` (which was just thrown on line 233 with a valid message) and re-throws it with an empty string. This discards the server error message.

- [ ] **Step 1: Fix the catch block**

In `AnthropicClient.swift`, change lines 237-238:

**Current code:**
```swift
} catch is AnthropicError {
    throw AnthropicError.requestFailed(statusCode: httpResponse.statusCode, message: "")
}
```

**New code:**
```swift
} catch let error as AnthropicError {
    throw error
}
```

- [ ] **Step 2: Run existing AnthropicClient tests**

Run: `cd CrateBotCore && swift test --filter AnthropicClientTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 3: Commit**

```bash
cd CrateBotCore && git add Sources/CrateBotCore/Networking/AnthropicClient.swift
git commit -m "fix: preserve error messages in AnthropicClient catch block

The catch block was matching AnthropicError and re-throwing with an
empty message, discarding the server error details. Now it re-throws
the original error with its message intact.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 7: Remove Dead Threshold Slider & Fix Decompression

### Task 7: Remove non-functional threshold slider from AddFallbackMappingSheet

**Files:**
- Modify: `CrateBot/Views/AddFallbackMappingSheet.swift:11,102-124,153`

**Context:** The threshold slider (lines 102-124) sets a local `@State` variable that's passed to `TagFallbackMapping` init, but the `threshold` property on `TagFallbackMapping` is deprecated and returns a constant 0.3. The slider does nothing.

- [ ] **Step 1: Remove the threshold state and slider**

In `AddFallbackMappingSheet.swift`:

1. Remove line 11: `@State private var threshold: Float = 0.3`

2. Remove the entire Section block for the slider (lines 102-124):
```swift
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Slider(value: $threshold, in: 0.1...0.9, step: 0.05)
                            ...
                        }
                    } header: {
                        Text("Confidence Threshold")
                    } footer: {
                        Text("Minimum confidence required to apply this tag. Lower = more tags, Higher = more accurate.")
                    }
```

3. In the `addMapping()` function (line 153), remove `threshold: threshold` from the init call:

**Current:**
```swift
let mapping = TagFallbackMapping(
    userTag: userTag.trimmingCharacters(in: .whitespaces),
    essentiaSource: selectedSource,
    essentiaLabel: selectedLabel,
    threshold: threshold
)
```

**New:**
```swift
let mapping = TagFallbackMapping(
    userTag: userTag.trimmingCharacters(in: .whitespaces),
    essentiaSource: selectedSource,
    essentiaLabel: selectedLabel
)
```

Note: Verify that TagFallbackMapping has an init without the threshold parameter, or that threshold has a default value. If it requires threshold, pass `0.3` as a constant instead of removing it.

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && xcodebuild -project CrateBot.xcodeproj -scheme CrateBot build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CrateBot/Views/AddFallbackMappingSheet.swift
git commit -m "fix: remove non-functional threshold slider from fallback mapping sheet

The slider mapped to a deprecated field on TagFallbackMapping that
returns a constant 0.3 regardless of the value set. Removing it
eliminates user confusion — the global strictness setting in
preferences controls threshold behavior.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

### Task 8: Fix decompression buffer size in FeatureCompression

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/Data/FeatureCompression.swift:10-41,56-57`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/FeatureCompressionTests.swift`

**Context:** The compression function doesn't store the original byte count. Decompression guesses with `data.count * 10`. For highly compressible data (e.g., low-variance features), actual decompressed size could exceed this estimate, causing silent failures.

- [ ] **Step 1: Write failing test for high compression ratio**

Add to `FeatureCompressionTests.swift`:

```swift
func testHighCompressionRatioRoundTrips() throws {
    // Highly compressible: same value repeated 10,000 times
    // LZ4 can achieve >50x compression on this pattern
    let original = [Float](repeating: 42.0, count: 10000)
    let compressed = original.toCompressedData()
    let decompressed = try [Float].fromCompressedData(compressed)
    XCTAssertEqual(original, decompressed)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd CrateBotCore && swift test --filter testHighCompressionRatioRoundTrips 2>&1 | tail -10`
Expected: May FAIL with decompressionFailed if compression ratio exceeds 10x.

- [ ] **Step 3: Store original byte count in compressed data**

In `FeatureCompression.swift`, modify `toCompressedData()` to prepend the original byte count:

**New `toCompressedData()`:**
```swift
public func toCompressedData() -> Data {
    guard !isEmpty else { return Data() }

    let byteCount = count * MemoryLayout<Float>.size
    let bytes = withUnsafeBytes { Data($0) }

    // Try to compress with LZ4
    let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
    defer { destinationBuffer.deallocate() }

    let compressedSize = bytes.withUnsafeBytes { sourceBuffer in
        compression_encode_buffer(
            destinationBuffer,
            byteCount,
            sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
            byteCount,
            nil,
            COMPRESSION_LZ4
        )
    }

    if compressedSize > 0 && compressedSize < byteCount {
        // Prepend original byte count as 4-byte little-endian UInt32
        var size = UInt32(byteCount).littleEndian
        var result = Data(bytes: &size, count: 4)
        result.append(Data(bytes: destinationBuffer, count: compressedSize))
        return result
    } else {
        // Return uncompressed data with marker
        var result = Data([0xFF])
        result.append(bytes)
        return result
    }
}
```

**New `fromCompressedData()`:**
```swift
public static func fromCompressedData(_ data: Data) throws -> [Float] {
    guard !data.isEmpty else { return [] }

    // Check for uncompressed marker
    if data.first == 0xFF {
        let bytes = data.dropFirst()
        let count = bytes.count / MemoryLayout<Float>.size
        return bytes.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(count))
        }
    }

    // Read original byte count from first 4 bytes
    let originalSize: Int
    if data.count >= 4 {
        let sizeBytes = data.prefix(4)
        let storedSize = sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        originalSize = Int(storedSize)
    } else {
        // Legacy format without size header — fall back to estimate
        originalSize = data.count * 10
    }

    let compressedData = data.count >= 4 ? data.dropFirst(4) : data
    let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: originalSize)
    defer { destinationBuffer.deallocate() }

    let decompressedSize = compressedData.withUnsafeBytes { sourceBuffer in
        compression_decode_buffer(
            destinationBuffer,
            originalSize,
            sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
            compressedData.count,
            nil,
            COMPRESSION_LZ4
        )
    }

    guard decompressedSize > 0 else {
        throw FeatureCompressionError.decompressionFailed
    }

    let floatCount = decompressedSize / MemoryLayout<Float>.size
    let floatBuffer = UnsafeRawPointer(destinationBuffer).bindMemory(to: Float.self, capacity: floatCount)
    return Array(UnsafeBufferPointer(start: floatBuffer, count: floatCount))
}
```

- [ ] **Step 4: Run all compression tests**

Run: `cd CrateBotCore && swift test --filter FeatureCompressionTests 2>&1 | tail -20`
Expected: All PASS including the new high-compression test.

- [ ] **Step 5: Commit**

```bash
cd CrateBotCore && git add Sources/CrateBotCore/Data/FeatureCompression.swift Tests/CrateBotCoreTests/FeatureCompressionTests.swift
git commit -m "fix: store original byte count in compressed data for safe decompression

LZ4 decompression requires knowing the output size. Previously this was
estimated as compressed_size * 10, which fails for highly compressible
data. Now the original byte count is prepended as a 4-byte header.
Legacy compressed data without the header falls back to the estimate.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Chunk 8: Final Verification

### Task 9: Run full test suite and verify

- [ ] **Step 1: Run all CrateBotCore tests**

Run: `cd CrateBotCore && swift test 2>&1 | tail -30`
Expected: All tests PASS.

- [ ] **Step 2: Build the Xcode project**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && xcodebuild -project CrateBot.xcodeproj -scheme CrateBot build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Review all changes**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && git diff --stat HEAD~8`
Verify: Only the files listed in the File Map were modified/created.

---

## Summary of Changes

| Fix | Impact | Risk |
|-----|--------|------|
| Linear calibration | Predictions no longer compressed toward 0.5 | Low — same interface, different math |
| 1.5:1 negative ratio | Classifiers less biased against tagging | Low — parameter change only |
| Remove fuzzy match | No more false positives from string matching | Low — explicit mappings still work |
| Tag normalization | Consistent case = consolidated training samples | Low — additive normalization |
| Cache raw features | Fresh augmentation each training run | Low — cache still valid |
| Error message fix | Debuggable API errors | None |
| Remove dead slider | Cleaner UI, no confusion | None |
| Safe decompression | No buffer overflows on high-compression data | Low — backward compatible |
