# Fresh Eyes Code Review: Training Pipeline

**Date:** 2026-01-28
**Reviewer:** OpenAI Codex (gpt-5.2-codex)
**Scope:** Complete training pipeline from user workflow perspective
**Tokens Used:** 227,087

---

## Executive Summary

Independent code review of the CrateBot training pipeline examining the complete user workflow:
1. Adding tracks to train on
2. Selecting tag categories in the lexicon
3. Selecting specific tags within each field category
4. Extracting features
5. Training the model
6. Applying the model via tagging to new tracks

Six issues identified ranging from critical to low severity, plus architectural questions about pipeline coherence.

---

## Findings

### 1. CRITICAL — Metadata Filename Mismatch Breaks Tagging

**Impact:** User-trained models fail to load metadata, causing multi-class classifiers to be missing and feature dimension mismatches.

**Problem:**
- Training writes metadata as `<modelName>.json` (e.g., `DJSet.json`)
- TaggingEngine hardcodes lookup for `metadata.json`
- Metadata never loads, causing cascading failures

**Affected Code:**
- `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift:638`
  ```swift
  let metadataURL = outputDirectory.appendingPathComponent("\(options.modelName).json")
  ```
- `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:199`
  ```swift
  let metadataURL = modelDirectory.appendingPathComponent("metadata.json")
  ```

**Consequences:**
1. Feature dimension detection fails → falls back to wrong config (1680 dims instead of 2192)
2. Multi-class classifiers (genre/timing/mood groups) never load
3. Category mapping lost → predictions not properly organized
4. Potential runtime crashes from dimension mismatches

**Fix:** Update TaggingEngine to accept model name parameter and look for `<modelName>.json`, consistent with how `ModelManager.listModels()` already works (line 65).

---

### 2. HIGH — Custom Descriptive Tags Silently Dropped

**Impact:** User-trained custom tags are lost during tagging without any warning.

**Problem:**
- `DescriptiveTagMapping.swift` contains a hardcoded list of ~50 tags
- `organize()` function only preserves tags in this list
- Custom tags like "Groovy", "Euphoric", "Hypnotic" silently disappear

**Affected Code:**
- `CrateBotCore/Sources/CrateBotCore/ML/DescriptiveTagMapping.swift:105-112`
  ```swift
  public static func organize(_ tags: [String]) -> [DescriptiveSubCategory: [String]] {
      var result: [DescriptiveSubCategory: [String]] = [:]
      for tag in tags {
          if let category = subCategory(for: tag) {
              result[category, default: []].append(tag)
          }
          // Tags not in mapping silently ignored!
      }
      return result
  }
  ```
- `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:551`

**Example:**
```
Model predicts: ["Funky", "Groovy", "Driving", "Euphoric"]
After organize(): ["Funky", "Driving"]  ← "Groovy" and "Euphoric" lost
```

**Fix:** Add `customTags: [String]` field to `UserTagPredictions` and preserve unrecognized tags instead of dropping them.

---

### 3. HIGH — Retraining with Same Model Name Leaves Stale Classifiers

**Impact:** Old tag classifiers persist after retraining, causing unexpected predictions.

**Problem:**
- Training creates models in `~/Models/<modelName>/` directory
- Directory is never cleaned before retraining
- TaggingEngine loads ALL `.mlmodel` files found

**Affected Code:**
- `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift:493-494`
  ```swift
  let outputDirectory = try await modelManager.modelsDirectory()
      .appendingPathComponent(options.modelName)
  // No cleanup of existing files!
  ```
- `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:188`
  ```swift
  let modelFiles = contents.filter { $0.pathExtension == "mlmodel" || $0.pathExtension == "mlmodelc" }
  ```

**Scenario:**
1. Train "DJSet" with tags: House, Techno, Chill
2. Retrain "DJSet" with tags: House, Ambient (removed Techno, Chill)
3. Directory still contains: House.mlmodel, Techno.mlmodel, Chill.mlmodel, Ambient.mlmodel
4. TaggingEngine loads all 4, including stale Techno and Chill

**Fix:** Clean output directory before training:
```swift
if fileManager.fileExists(atPath: outputDirectory.path) {
    try fileManager.removeItem(at: outputDirectory)
}
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
```

---

### 4. MEDIUM — Training Pause/Stop is UI-Only

**Impact:** Users believe they can pause or cancel training, but the pipeline continues in background.

**Problem:**
- TrainView has Pause and Stop buttons that toggle UI state
- TrainingCoordinator and data collectors don't observe these signals
- Training continues consuming resources even after "cancellation"

**Affected Code:**
- `CrateBot/Views/TrainView.swift:240`
  ```swift
  @Published var isCancelled: Bool = false
  ```
- `CrateBot/Views/TrainView.swift:568-578` (Pause/Resume buttons only toggle `isPaused`)
- TrainingCoordinator has no cancellation token or pause checking

**Fix:** Implement cooperative cancellation:
1. Pass cancellation token to TrainingCoordinator
2. Check `Task.isCancelled` at key points in training loop
3. Implement actual pause by suspending between batches

---

### 5. MEDIUM — ID3 Field Mapping Inconsistencies

**Impact:** User-selected ID3 fields may be ignored or written to wrong locations.

**Problem:**
- Some selectable fields (Category, Movement, Work, BPM) map to `nil` for training
- These fall back to `.comments` during writing, losing intended structure
- TaggingSettings UI is ignored for user-model output (always uses TagMappingConfiguration)

**Affected Code:**
- `CrateBot/Views/TrainView.swift:60, 76` (ID3Field enum with incomplete mappings)
- `CrateBot/Views/TaggingSettingsSheet.swift:48` (UI allows selecting unmapped fields)
- `CrateBot/Views/TaggingView.swift:768` (Uses training mapping, not tagging settings)

**User Confusion:**
- User selects "Movement" field in UI
- Training silently ignores it (maps to nil)
- Writing falls back to Comments
- User's organizational structure is lost

**Fix:** Either:
1. Remove unmapped fields from UI, or
2. Implement proper mappings for all exposed fields

---

### 6. LOW/MEDIUM — Tag Counts Overstate Usable Training Data

**Impact:** Users select tags that later fall below minimum samples without warning.

**Problem:**
- Tag discovery scanning doesn't perform audio validation
- Training data collection excludes invalid audio files
- Tag counts shown during selection don't reflect actual usable samples

**Affected Code:**
- `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift:234` (discovery skips validation)
- `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift:451` (training validates and excludes)

**Scenario:**
1. Tag discovery shows "Funky" has 60 tracks
2. User selects it (minimum is 50)
3. During training, 15 tracks have invalid audio and are excluded
4. "Funky" now has only 45 valid samples → silently skipped
5. User doesn't know why their tag wasn't trained

**Fix:** Either:
1. Run audio validation during discovery (slower but accurate), or
2. Show warning during training when tags drop below threshold

---

## Open Questions

### 1. Metadata Filename Convention
Which should be canonical—`metadata.json` or `<modelName>.json`?

**Recommendation:** Use `<modelName>.json` and update TaggingEngine. This:
- Supports multiple models with separate metadata
- Matches existing ModelManager.listModels() pattern
- Is more explicit and debuggable

### 2. Python CLI/Lexicon Workflow Status
The Python CLI has its own lexicon/category system not exposed in Swift UI:
- `python/src/core/lexicon.py`
- `python/src/core/auto_tagger.py`

**Question:** Is this still a supported workflow? If so, the two pipelines have diverged significantly and may produce inconsistent results.

### 3. Unused TrainingOptions Fields
`TrainingOptions.validationSplit` and `minSamplesPerTag` are set by UI but never used:

```swift
// TrainingCoordinator.swift:97-101
public let validationSplit: Double      // ← Set but ignored
public let minSamplesPerTag: Int        // ← Set but ignored
```

The coordinator reads from `TrainingConfiguration` instead:
```swift
// TrainingCoordinator.swift:360
let minSamples = options.configuration.minSamplesPerTag
```

**Question:** Should these options be authoritative, or should they be removed from the UI to avoid confusion?

---

## Recommendations

### Immediate Fixes (Issues 1-3)
These are breaking bugs that should be fixed immediately:

1. **Metadata naming** — Update TaggingEngine to load `<modelName>.json`
2. **Custom tags** — Add `customTags` field to preserve user-trained tags
3. **Stale models** — Clean output directory before training

### Short-term Improvements (Issues 4-5)
User experience issues that should be addressed:

4. **Cancellation** — Implement cooperative cancellation in training pipeline
5. **ID3 mapping** — Audit and fix field mapping consistency

### Long-term Considerations (Issue 6)
Quality of life improvements:

6. **Tag counts** — Add validation during discovery or warning during training

---

## Files Examined

| File | Purpose |
|------|---------|
| `CrateBot/Views/TrainView.swift` | Training UI and view model |
| `CrateBot/Views/TaggingView.swift` | Tagging workflow |
| `CrateBot/Views/TaggingSettingsSheet.swift` | Tagging configuration UI |
| `CrateBot/App/AppState.swift` | Application state management |
| `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift` | Training orchestration |
| `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift` | Data collection and feature extraction |
| `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` | Inference and prediction |
| `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift` | Model training |
| `CrateBotCore/Sources/CrateBotCore/ML/ModelManager.swift` | Model discovery and loading |
| `CrateBotCore/Sources/CrateBotCore/ML/DescriptiveTagMapping.swift` | Tag categorization |
| `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift` | Metadata structure |
| `python/src/core/lexicon.py` | Python lexicon system |
| `python/src/core/auto_tagger.py` | Python training pipeline |

---

## Change Summary

**Review only; no code changes made.**

Ready to implement fixes for issues 1-3 upon approval.
