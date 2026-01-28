# Python Pipeline Removal & Swift Training Improvements

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove all Python training pipeline references from documentation and code, then improve the native Swift training pipeline with configurable tag groups and better validation.

**Architecture:** Documentation-first cleanup (README, SWIFT-TRAINING-PIPELINE.md, code comments), followed by Swift code improvements (TagGroupRegistry, TrainingDataCollector, progress reporting).

**Tech Stack:** Swift, SwiftUI, CoreML, CreateML

**Worktree:** Main branch (documentation and incremental improvements)

---

## Phase 1: Documentation Cleanup

### Task 1.1: Rewrite SWIFT-TRAINING-PIPELINE.md (Remove Python Comparison)

**Files:**
- Modify: `docs/SWIFT-TRAINING-PIPELINE.md`

**Step 1: Read current file and understand structure**

The file currently has:
- Lines 1-68: Swift pipeline documentation (KEEP)
- Lines 70-100: Python pipeline comparison (REMOVE)
- Lines 102-120: Feature comparison table (REMOVE Python column)
- Lines 122-168: Swift implementation details (KEEP, UPDATE)
- Lines 170-228: Recommendations and file list (KEEP, UPDATE)

**Step 2: Rewrite the file**

Replace entire contents with:

```markdown
# Swift Training Pipeline

## Overview

CrateBot uses a native Swift/CoreML training pipeline for audio tag classification. The pipeline extracts audio features using pre-trained neural networks and trains binary classifiers for each tag using CreateML's MLBoostedTreeClassifier.

## Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SWIFT TRAINING PIPELINE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. DATA COLLECTION (TrainingDataCollector.swift)                          │
│     ├─ Scan directories for MP3 files                                      │
│     ├─ Read ID3 tags using configurable TagFieldMapping                    │
│     │   └─ genre=TCON, timing=TALB/TPE2 (user configurable), mood=TIT1/TALB│
│     ├─ Validate audio files (filter problematic files)                     │
│     └─ Create TaggedTrack objects                                          │
│                                                                             │
│  2. FEATURE EXTRACTION (CombinedFeatureExtractor.swift)                    │
│     ├─ Load audio at 16kHz                                                 │
│     ├─ EffNet embeddings: 1280 dimensions                                  │
│     ├─ Genre activations: 400 dimensions                                   │
│     ├─ CLAP embeddings: 512 dimensions                                     │
│     └─ Total: 2192-dim feature vector                                      │
│                                                                             │
│  3. AUGMENTATION (AudioAugmenter.swift)                                    │
│     ├─ SpecAugment: Time/frequency masking                                 │
│     ├─ Mixup: Beta distribution mixing (alpha=0.4)                         │
│     └─ Feature noise: 2% Gaussian noise                                    │
│                                                                             │
│  4a. MULTI-CLASS TRAINING (TagGroupRegistry + ModelTrainer)                │
│     ├─ Identify tag groups (configurable mutually exclusive tags)          │
│     ├─ Generate multi-class data per group                                 │
│     ├─ Train MLBoostedTreeClassifier per group                             │
│     └─ Remove grouped tags from binary training                            │
│                                                                             │
│  4b. BINARY TRAINING (ModelTrainer.swift)                                  │
│     ├─ Generate balanced positive/negative samples                         │
│     ├─ Log contrastive loss (diagnostic)                                   │
│     ├─ Apply Mixup augmentation                                            │
│     ├─ Z-score normalize features                                          │
│     ├─ Train MLBoostedTreeClassifier per tag                               │
│     │   └─ Parameters: maxDepth=6, iterations=100, stepSize=0.3            │
│     └─ Validate with holdout set (20%)                                     │
│                                                                             │
│  5. PACKAGING (TrainingCoordinator.swift)                                  │
│     ├─ Save .mlmodel files                                                 │
│     ├─ Create metadata.json with categories and tag groups                 │
│     └─ Clean up checkpoints                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Components

| Component | File | Purpose |
|-----------|------|---------|
| **TrainingCoordinator** | `ML/TrainingCoordinator.swift` | Orchestrates full pipeline |
| **TrainingDataCollector** | `ML/TrainingDataCollector.swift` | Scans MP3s, reads ID3, extracts features |
| **CombinedFeatureExtractor** | `Audio/CombinedFeatureExtractor.swift` | EffNet + Genres + CLAP = 2192 dims |
| **ModelTrainer** | `ML/ModelTrainer.swift` | CreateML MLBoostedTreeClassifier |
| **TagGroupRegistry** | `ML/TagGroupRegistry.swift` | Configurable multi-class tag groups |
| **MultiClassTrainingDataGenerator** | `ML/MultiClassTrainingDataGenerator.swift` | Generates multi-class data |
| **AudioAugmenter** | `ML/AudioAugmenter.swift` | Mixup, SpecAugment |
| **ContrastiveLoss** | `ML/ContrastiveLoss.swift` | Diagnostic loss logging |
| **ID3Manager** | `Tags/ID3Manager.swift` | Read/write ID3 tags |

---

## Feature Extraction

### 2192-Dimensional Feature Vector

The Swift pipeline extracts rich audio features using three pre-trained models:

| Model | Dimensions | Purpose |
|-------|------------|---------|
| Discogs-EffNet | 1280 | General audio embeddings trained on millions of tracks |
| Jamendo Genres | 400 | Genre classification activations |
| CLAP | 512 | Semantic audio-text embeddings |

### Audio Processing

```
Audio File (any format/sample rate)
         ↓
[Resample to 16kHz mono]
         ↓
[Generate Mel Spectrogram]
    - Frame size: 512 samples (32ms)
    - Hop size: 256 samples (16ms)
    - Mel bands: 96
    - Time frames: 128
         ↓
[Run Feature Extractors]
         ↓
2192-dimensional embedding
```

---

## Multi-Class Tag Groups

Tag groups define mutually exclusive tags that should be trained as multi-class classifiers (softmax) rather than independent binary classifiers.

### Configuration

Tag groups are configurable in the Training UI. Default groups:

```swift
"BassType": ["Punchy", "Walking", "BoomingBass", "GrindyBass"]
"VocalType": ["Singing", "Chanting", "Spoken Word", "Rap", "Instrumental"]
"Energy": ["Low", "Medium", "High", "Peak"]
"Cultural": ["Asian", "Latin", "African", "MiddleEastern", "European"]
```

### How It Works

1. During training, tags matching these groups are trained as multi-class (softmax)
2. These tags are excluded from binary training
3. At inference, the model predicts ONE tag from each group

**Important:** Configure tag groups to match your actual vocabulary. If you don't have tags like "Punchy" or "Walking", these groups won't help.

---

## Augmentation

### Mixup (Default: Enabled)

Combines two training samples to create synthetic examples:

```
mixed_features = λ · sample1 + (1-λ) · sample2
```

- λ is drawn from Beta(0.4, 0.4) distribution
- 30% of training data is augmented
- Uses dominant label for classification

**Benefits:** Regularization, smooth decision boundaries, better generalization.

### SpecAugment

Time and frequency masking applied to mel spectrograms before feature extraction.

### Feature Noise

2% Gaussian noise added to feature vectors during training.

---

## Training Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Min samples per tag | 50 | Tags with fewer samples are skipped |
| Max negative ratio | 3:1 | Prevents class imbalance |
| Max tree depth | 6 | MLBoostedTreeClassifier depth |
| Boosting iterations | 100 | Number of trees |
| Learning rate | 0.3 | Step size for gradient boosting |
| Validation split | 20% | Holdout for accuracy estimation |

---

## Contrastive Loss Diagnostics

Before training each tag, the pipeline computes supervised contrastive loss to measure how well features separate classes.

- **Loss < 2.0:** Excellent separation, expect high accuracy
- **Loss 2.0-5.0:** Good separation, reasonable accuracy
- **Loss > 5.0:** Poor separation, tag may be difficult to learn

This is diagnostic only (CreateML doesn't support custom losses), but helps identify problematic tags.

---

## Checkpoint System

Feature extraction is expensive (~2-5 seconds per track). The checkpoint system enables:

- **Resume interrupted training** without re-extracting features
- **Detect tag modifications** that require re-training
- **Cache features** for faster iteration

### Checkpoint Location

```
~/Library/Application Support/CrateBot/Checkpoints/{modelName}.checkpoint.json
```

### Compatibility

A checkpoint is invalidated if:
- Source directories changed
- ID3 tags were modified (detected via hash)
- Pipeline version changed

---

## Model Output

### Directory Structure

```
~/Library/Application Support/CrateBot/Models/{ModelName}/
├── house.mlmodel           # Binary classifier for "house"
├── techno.mlmodel          # Binary classifier for "techno"
├── EnergyGroup.mlmodel     # Multi-class classifier for Energy
├── ...
└── metadata.json           # Model metadata
```

### Metadata Format

```json
{
  "name": "ModelName",
  "version": "1.0.0",
  "pipelineVersion": "a1b2c3d4e5f6g7h8",
  "trainedAt": "2024-01-15T12:00:00Z",
  "trainingFileCount": 450,
  "categories": ["General"],
  "tags": {
    "General": ["house", "techno", "energetic", "chill"]
  },
  "tagGroups": {
    "Energy": ["Low", "Medium", "High", "Peak"]
  },
  "accuracy": 0.847
}
```

---

## Troubleshooting

### Common Skip Reasons

| Reason | Solution |
|--------|----------|
| "Insufficient samples (50 required)" | Add more tracks with this tag |
| "Training failed: NaN in features" | Check for corrupted audio files |
| "Zero negative samples" | Tag is too common (all tracks have it) |

### Feature Extraction Failures

| Error | Cause | Solution |
|-------|-------|----------|
| "Insufficient data" | Track < 2.27 seconds | Use longer tracks |
| "Invalid buffer" | Corrupted audio | Re-encode file |
| "NaN/Inf in features" | Audio anomaly | Exclude track |

### Debugging

Check logs at: `~/Library/Application Support/CrateBot/debug.log`

---

## Code References

| Component | File | Key Functions |
|-----------|------|---------------|
| Training orchestration | `ML/TrainingCoordinator.swift` | `train()`, `currentPipelineVersion()` |
| Feature extraction | `Audio/CombinedFeatureExtractor.swift` | `extractFeatures()` |
| Data collection | `ML/TrainingDataCollector.swift` | `collect()`, `extractFeatures()` |
| Model training | `ML/ModelTrainer.swift` | `trainModels()` |
| Multi-class groups | `ML/TagGroupRegistry.swift` | `groups`, `isMultiClass()` |
| Checkpoint system | `ML/TrainingCheckpoint.swift` | `save()`, `load()`, `isCompatible()` |
| Inference | `ML/TaggingEngine.swift` | `analyze()`, `loadModel()` |
```

**Step 3: Commit**

```bash
git add docs/SWIFT-TRAINING-PIPELINE.md
git commit -m "docs: rewrite SWIFT-TRAINING-PIPELINE.md as Swift-only documentation

- Remove Python pipeline comparison section
- Remove feature comparison table
- Focus on Swift implementation details
- Add configurable tag groups documentation
- Update code references"
```

---

### Task 1.2: Rewrite README.md (Remove Python References)

**Files:**
- Modify: `README.md`

**Step 1: Rewrite the README**

Replace entire contents with:

```markdown
# CrateBot 5

Audio fingerprinting and intelligent music analysis suite for DJs.

**CrateBot** uses machine learning to analyze your music library and suggest songs you might want to use while playing live. Think of it as a DJ's intelligent crate-digging assistant.

> Built with Claude Code by someone who has basically never written a line of code in his life. See: [The Road Runner Economy](https://nraford7.github.io/road-runner-economy/)

## What It Does

- **ML-powered tagging**: Predict Genre, Timing, Mood, and Descriptive tags for your tracks
- **2192-dimensional feature vectors**: EffNet (1280) + Jamendo genres (400) + CLAP (512) embeddings
- **Native Swift training**: Train custom models on your own tagged library using CoreML
- **Vibe generation**: Claude API-powered tags that capture what makes each track *distinctive*
- **Mnemonic anchors**: Album-art-like memory hooks (2-3 word phrases that *feel* like the track)
- **Hook detection**: Lyrics-first detection with Whisper fallback for finding memorable vocal moments
- **Real-time progress**: Live updates for long analysis tasks
- **Checkpoint recovery**: Resume interrupted training

## Vibe System

CrateBot generates two complementary tags for each track:

### Short Vibe Tag
**Format:** `[ENERGY] [DISTINCTIVE THING] [MOMENT]`

Identifies what makes the track unique - the thing you'd tell a friend to listen for.

```
DARK FLUTE MELODY PEAK
HARD ACID 303 SQUELCH PEAK
JOYFUL KALIMBA GROOVE OPENER
DREAMY STRINGS PIANO BLEND FLOATER
```

### Mnemonic Anchor
**Format:** `[synesthetic modifier] + [concrete anchor]`

A 2-3 word phrase that works like album art in text form - triggers recall through association, not description.

```
sweating serpent
chrome shaman
golden grandmother
velvet cathedral
```

The modifier translates sonic qualities to other senses (warm, dusty, chrome, velvet). The anchor is something you can picture (wizard, panther, cathedral, shaman).

## Hook Detection

CrateBot uses a **lyrics-first** approach for detecting hooks (memorable vocal phrases):

1. **Fetch lyrics** from free APIs (LRCLIB, Lyrics.ovh)
2. **Analyze for repetition** - find chorus sections and repeated phrases
3. **Fall back to Whisper** transcription if no lyrics available

This dramatically improves accuracy for known tracks since lyrics are "ground truth" with no hallucination risk.

See [docs/LYRICS-FIRST-HOOK-DETECTION.md](docs/LYRICS-FIRST-HOOK-DETECTION.md) for details.

## Architecture

Built with **SwiftUI** and **CoreML** for fully native macOS performance.

```
CrateBot5/
├── CrateBot.xcodeproj    # Xcode project
├── CrateBot/             # SwiftUI app
│   ├── App/              # App entry, state management
│   └── Views/            # SwiftUI views
├── CrateBotCore/         # Swift Package
│   ├── Audio/            # Feature extraction, playback
│   ├── ML/               # Training, inference (CoreML)
│   ├── Tags/             # ID3 tag management
│   ├── Data/             # SwiftData models, caching
│   ├── Integrations/     # External API clients
│   └── Resources/        # ML models (.mlpackage)
├── CrateBotModelLab/     # Model experimentation app
└── Models/               # Trained models directory
```

## Getting Started

1. **Open in Xcode**: `open CrateBot.xcodeproj`
2. **Build and Run**: ⌘R
3. **Add Music Folders**: Grant access to your DJ library
4. **Train a Model**: Tag some tracks, then train on your library

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Anthropic API key (optional, for vibe generation)

## Key Features

| Feature | Description |
|---------|-------------|
| Native Swift | No Python dependencies, pure macOS performance |
| Feature caching | SwiftData persistence for extracted features |
| Configurable tag groups | Define mutually exclusive tags for multi-class training |
| Checkpoint recovery | Resume interrupted training sessions |
| Security-scoped bookmarks | Sandbox-safe access to music folders |

## Training Your Own Model

1. **Tag your tracks** using ID3 metadata (Genre, Mood, etc.)
2. **Configure field mapping** to tell CrateBot which ID3 frames to read
3. **Set up tag groups** for mutually exclusive categories (e.g., Energy: Low/Medium/High)
4. **Train** - CrateBot extracts features and trains CoreML classifiers
5. **Use** - Tag new tracks with your trained model

See [docs/SWIFT-TRAINING-PIPELINE.md](docs/SWIFT-TRAINING-PIPELINE.md) for detailed pipeline documentation.

## Status

Work in progress. DJ'ing is a main side quest.

---

*Part of the [Road Runner Economy](https://nraford7.github.io/road-runner-economy/) - built in hours, not months.*
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README.md for native Swift architecture

- Remove all Python/FastAPI references
- Update architecture diagram to Swift-only
- Update requirements to macOS/Xcode
- Remove Python setup instructions
- Add native Swift feature highlights"
```

---

### Task 1.3: Update LYRICS-FIRST-HOOK-DETECTION.md

**Files:**
- Modify: `docs/LYRICS-FIRST-HOOK-DETECTION.md`

**Step 1: Read current file to find Python code examples**

```bash
grep -n "python\|\.py" docs/LYRICS-FIRST-HOOK-DETECTION.md
```

**Step 2: Replace Python code example with Swift**

Find the Python code block (around lines 60-70) and replace with:

```swift
// Using HookDetector from CrateBotCore
let detector = HookDetector()
let result = try await detector.detectHook(
    in: fileURL,
    artist: "Artist Name",
    title: "Song Title"
)
print(result.hook ?? "No hook detected")  // "feel the groove tonight"
```

**Step 3: Remove any Python-specific implementation details**

Update any references to `CachedHookTranscriber` or Python classes.

**Step 4: Commit**

```bash
git add docs/LYRICS-FIRST-HOOK-DETECTION.md
git commit -m "docs: update hook detection docs with Swift examples

- Replace Python code example with Swift HookDetector usage
- Remove Python implementation references"
```

---

### Task 1.4: Update Swift Code Comments

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/Integrations/HookDetector.swift:4`
- Modify: `CrateBotCore/Sources/CrateBotCore/Integrations/VibeGenerator.swift:57`

**Step 1: Update HookDetector.swift comment**

Change line 4 from:
```swift
/// Detects memorable vocal hooks via the Python backend (Whisper-powered)
```

To:
```swift
/// Detects memorable vocal hooks using lyrics-first approach with Whisper fallback
```

**Step 2: Update VibeGenerator.swift comment**

Change line 57 from:
```swift
/// Actor for generating AI-powered vibe tags via the Python backend
```

To:
```swift
/// Actor for generating AI-powered vibe tags via Claude API
```

**Step 3: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Integrations/HookDetector.swift
git add CrateBotCore/Sources/CrateBotCore/Integrations/VibeGenerator.swift
git commit -m "chore: remove Python backend references from Swift comments

- Update HookDetector docstring
- Update VibeGenerator docstring"
```

---

## Phase 2: Swift Pipeline Improvements

### Task 2.1: Add Configurable Tag Groups to TagGroupRegistry

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/TagGroupRegistryTests.swift` (if not exists)

**Step 1: Read current TagGroupRegistry implementation**

```bash
cat CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift
```

Understand the current hardcoded groups structure.

**Step 2: Write failing test for configurable groups**

```swift
import XCTest
@testable import CrateBotCore

final class TagGroupRegistryConfigurableTests: XCTestCase {
    func testCustomGroupsOverrideDefaults() {
        let customGroups: [String: [String]] = [
            "Vibe": ["Dark", "Light", "Neutral"],
            "Tempo": ["Slow", "Medium", "Fast"]
        ]

        let registry = TagGroupRegistry(customGroups: customGroups)

        XCTAssertEqual(registry.groups.count, 2)
        XCTAssertTrue(registry.groups.keys.contains("Vibe"))
        XCTAssertTrue(registry.groups.keys.contains("Tempo"))
        XCTAssertFalse(registry.groups.keys.contains("BassType"))  // Default removed
    }

    func testEmptyCustomGroupsUsesDefaults() {
        let registry = TagGroupRegistry(customGroups: nil)

        XCTAssertTrue(registry.groups.keys.contains("BassType"))
        XCTAssertTrue(registry.groups.keys.contains("Energy"))
    }

    func testIsMultiClassWithCustomGroups() {
        let customGroups = ["Vibe": ["Dark", "Light"]]
        let registry = TagGroupRegistry(customGroups: customGroups)

        XCTAssertTrue(registry.isMultiClass(tag: "Dark"))
        XCTAssertTrue(registry.isMultiClass(tag: "Light"))
        XCTAssertFalse(registry.isMultiClass(tag: "Punchy"))  // Not in custom groups
    }
}
```

**Step 3: Run test to verify it fails**

```bash
cd CrateBotCore && swift test --filter TagGroupRegistryConfigurableTests
```

Expected: FAIL - initializer doesn't accept customGroups

**Step 4: Implement configurable groups**

Update `TagGroupRegistry.swift`:

```swift
public struct TagGroupRegistry: Sendable {
    /// The tag groups (group name -> array of mutually exclusive tags)
    public let groups: [String: [String]]

    /// Default tag groups used when no custom groups are provided
    public static let defaultGroups: [String: [String]] = [
        "BassType": ["Punchy", "Walking", "BoomingBass", "GrindyBass"],
        "VocalType": ["Singing", "Chanting", "Spoken Word", "Rap", "Instrumental"],
        "Energy": ["Low", "Medium", "High", "Peak"],
        "Cultural": ["Asian", "Latin", "African", "MiddleEastern", "European"]
    ]

    /// Initialize with custom groups, or use defaults if nil
    public init(customGroups: [String: [String]]? = nil) {
        self.groups = customGroups ?? Self.defaultGroups
    }

    /// Check if a tag belongs to any multi-class group
    public func isMultiClass(tag: String) -> Bool {
        groups.values.contains { $0.contains(tag) }
    }

    /// Get the group name for a tag, if it belongs to one
    public func groupName(for tag: String) -> String? {
        groups.first { $0.value.contains(tag) }?.key
    }

    /// Get all tags that should be excluded from binary training
    public var multiClassTags: Set<String> {
        Set(groups.values.flatMap { $0 })
    }
}
```

**Step 5: Run test to verify it passes**

```bash
cd CrateBotCore && swift test --filter TagGroupRegistryConfigurableTests
```

Expected: PASS

**Step 6: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift
git add CrateBotCore/Tests/CrateBotCoreTests/ML/TagGroupRegistryTests.swift
git commit -m "feat: make TagGroupRegistry accept custom tag groups

- Add customGroups parameter to initializer
- Move hardcoded groups to defaultGroups static property
- Custom groups completely replace defaults when provided
- Enables user-configurable multi-class training"
```

---

### Task 2.2: Add Feature Dimension Validation to TrainingDataCollector

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift`

**Step 1: Read current implementation**

```bash
cat CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift | head -100
```

**Step 2: Find where features are collected and add validation**

Add explicit validation after feature extraction:

```swift
// After extracting features for a track
let features = try await extractor.extractFeatures(from: buffer)

// Validate feature dimensions
let expectedDimensions = 2192  // EffNet(1280) + Genres(400) + CLAP(512)
if features.count != expectedDimensions {
    logger.warning("Track \(url.lastPathComponent) has \(features.count) features, expected \(expectedDimensions) - skipping")
    continue
}

// Check for NaN/Inf
if features.contains(where: { !$0.isFinite }) {
    logger.warning("Track \(url.lastPathComponent) has non-finite features - skipping")
    continue
}
```

**Step 3: Add a SkipReason enum for better reporting**

```swift
public enum TrackSkipReason: String, Sendable {
    case featureDimensionMismatch = "Feature dimension mismatch"
    case nonFiniteFeatures = "Non-finite values in features"
    case audioTooShort = "Audio too short"
    case fileReadError = "File read error"
    case noTags = "No tags found"
}

public struct SkippedTrack: Sendable {
    public let url: URL
    public let reason: TrackSkipReason
    public let details: String?
}
```

**Step 4: Update TrainingProgress to include skipped tracks**

```swift
public struct TrainingProgress: Sendable {
    // ... existing properties
    public let skippedTracks: [SkippedTrack]
}
```

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift
git commit -m "feat: add explicit feature dimension validation in TrainingDataCollector

- Validate feature count matches expected 2192 dimensions
- Check for NaN/Inf values before training
- Add SkipReason enum for detailed skip reporting
- Log warnings for skipped tracks with reasons"
```

---

### Task 2.3: Add Per-Item Training Progress

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingProgress.swift` (or wherever progress is defined)

**Step 1: Read current TrainingProgress structure**

```bash
grep -r "TrainingProgress" CrateBotCore/Sources --include="*.swift" -l
```

**Step 2: Enhance TrainingProgress with per-item details**

```swift
public struct TrainingProgress: Sendable {
    public enum Phase: String, Sendable {
        case collecting = "Collecting files"
        case discoveringTags = "Discovering tags"
        case extractingFeatures = "Extracting features"
        case trainingModels = "Training models"
        case packaging = "Packaging model"
        case complete = "Complete"
        case failed = "Failed"
    }

    public let phase: Phase
    public let current: Int
    public let total: Int
    public let currentItem: String?  // e.g., "house.mlmodel" or "track001.mp3"
    public let accuracy: Double?     // For training phase, per-tag accuracy
    public let message: String?

    public var progress: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    public init(
        phase: Phase,
        current: Int = 0,
        total: Int = 0,
        currentItem: String? = nil,
        accuracy: Double? = nil,
        message: String? = nil
    ) {
        self.phase = phase
        self.current = current
        self.total = total
        self.currentItem = currentItem
        self.accuracy = accuracy
        self.message = message
    }
}
```

**Step 3: Update TrainingCoordinator to report per-item progress**

In the feature extraction loop:
```swift
for (index, track) in tracks.enumerated() {
    await progressHandler?(TrainingProgress(
        phase: .extractingFeatures,
        current: index + 1,
        total: tracks.count,
        currentItem: track.url.lastPathComponent
    ))
    // ... extract features
}
```

In the model training loop:
```swift
for (index, tag) in viableTags.enumerated() {
    await progressHandler?(TrainingProgress(
        phase: .trainingModels,
        current: index + 1,
        total: viableTags.count,
        currentItem: "\(tag).mlmodel"
    ))
    // ... train model

    // After training, report accuracy
    await progressHandler?(TrainingProgress(
        phase: .trainingModels,
        current: index + 1,
        total: viableTags.count,
        currentItem: "\(tag).mlmodel",
        accuracy: validationAccuracy
    ))
}
```

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingProgress.swift
git commit -m "feat: add per-item progress reporting during training

- Report current file during feature extraction
- Report current tag and accuracy during model training
- Add currentItem and accuracy fields to TrainingProgress
- Enables granular progress UI updates"
```

---

### Task 2.4: Add Training Configuration Struct

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/TrainingConfiguration.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingConfigurationTests.swift`

**Step 1: Write failing test**

```swift
import XCTest
@testable import CrateBotCore

final class TrainingConfigurationTests: XCTestCase {
    func testDefaultValues() {
        let config = TrainingConfiguration()

        XCTAssertEqual(config.minSamplesPerTag, 50)
        XCTAssertEqual(config.maxNegativeRatio, 3.0)
        XCTAssertEqual(config.mixupAlpha, 0.4)
        XCTAssertEqual(config.mixupRatio, 0.3)
        XCTAssertEqual(config.featureNoisePercent, 0.02)
        XCTAssertEqual(config.validationSplit, 0.2)
        XCTAssertTrue(config.enableMixup)
        XCTAssertTrue(config.enableSpecAugment)
    }

    func testCustomConfiguration() {
        let config = TrainingConfiguration(
            minSamplesPerTag: 100,
            maxNegativeRatio: 5.0,
            enableMixup: false
        )

        XCTAssertEqual(config.minSamplesPerTag, 100)
        XCTAssertEqual(config.maxNegativeRatio, 5.0)
        XCTAssertFalse(config.enableMixup)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd CrateBotCore && swift test --filter TrainingConfigurationTests
```

Expected: FAIL - TrainingConfiguration not defined

**Step 3: Implement TrainingConfiguration**

```swift
import Foundation

/// Configuration options for the training pipeline
public struct TrainingConfiguration: Codable, Sendable, Equatable {
    /// Minimum positive samples required to train a tag classifier
    public var minSamplesPerTag: Int

    /// Maximum negative:positive ratio to prevent class imbalance
    public var maxNegativeRatio: Double

    /// Mixup augmentation alpha parameter (Beta distribution)
    public var mixupAlpha: Float

    /// Ratio of training data to augment with mixup
    public var mixupRatio: Float

    /// Gaussian noise percentage added to features
    public var featureNoisePercent: Float

    /// Fraction of data held out for validation
    public var validationSplit: Double

    /// Whether to apply mixup augmentation
    public var enableMixup: Bool

    /// Whether to apply SpecAugment
    public var enableSpecAugment: Bool

    /// MLBoostedTreeClassifier max depth
    public var treeMaxDepth: Int

    /// MLBoostedTreeClassifier iterations
    public var treeIterations: Int

    /// MLBoostedTreeClassifier step size (learning rate)
    public var treeStepSize: Double

    public init(
        minSamplesPerTag: Int = 50,
        maxNegativeRatio: Double = 3.0,
        mixupAlpha: Float = 0.4,
        mixupRatio: Float = 0.3,
        featureNoisePercent: Float = 0.02,
        validationSplit: Double = 0.2,
        enableMixup: Bool = true,
        enableSpecAugment: Bool = true,
        treeMaxDepth: Int = 6,
        treeIterations: Int = 100,
        treeStepSize: Double = 0.3
    ) {
        self.minSamplesPerTag = minSamplesPerTag
        self.maxNegativeRatio = maxNegativeRatio
        self.mixupAlpha = mixupAlpha
        self.mixupRatio = mixupRatio
        self.featureNoisePercent = featureNoisePercent
        self.validationSplit = validationSplit
        self.enableMixup = enableMixup
        self.enableSpecAugment = enableSpecAugment
        self.treeMaxDepth = treeMaxDepth
        self.treeIterations = treeIterations
        self.treeStepSize = treeStepSize
    }

    /// Default configuration
    public static let `default` = TrainingConfiguration()
}
```

**Step 4: Run test to verify it passes**

```bash
cd CrateBotCore && swift test --filter TrainingConfigurationTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingConfiguration.swift
git add CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingConfigurationTests.swift
git commit -m "feat: add TrainingConfiguration for customizable training parameters

- Expose all training hyperparameters
- Sensible defaults matching current behavior
- Codable for persistence
- Enables advanced training UI options"
```

---

### Task 2.5: Wire TrainingConfiguration into TrainingCoordinator

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift`
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift`

**Step 1: Update TrainingCoordinator to accept configuration**

```swift
public func train(
    directories: [URL],
    modelName: String,
    configuration: TrainingConfiguration = .default,
    tagGroups: [String: [String]]? = nil,
    progressHandler: ((TrainingProgress) async -> Void)? = nil
) async throws -> URL {
    // Use configuration.minSamplesPerTag instead of hardcoded 50
    // Use configuration.maxNegativeRatio instead of hardcoded 3.0
    // Pass configuration to ModelTrainer
    // ...
}
```

**Step 2: Update ModelTrainer to use configuration**

```swift
public func trainModels(
    tracks: [TaggedTrack],
    tags: [String],
    configuration: TrainingConfiguration
) async throws -> [URL] {
    // Use configuration.treeMaxDepth, treeIterations, treeStepSize
    // Use configuration.enableMixup, mixupAlpha, mixupRatio
    // ...
}
```

**Step 3: Update BinaryTrainingDataGenerator**

Change static properties to use configuration:

```swift
public func generateTrainingData(
    for tagName: String,
    from tracks: [TaggedTrack],
    configuration: TrainingConfiguration
) -> (positive: [TaggedTrack], negative: [TaggedTrack])? {
    // Use configuration.minSamplesPerTag
    // Use configuration.maxNegativeRatio
}
```

**Step 4: Run existing tests to ensure no regressions**

```bash
cd CrateBotCore && swift test
```

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift
git add CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift
git add CrateBotCore/Sources/CrateBotCore/ML/BinaryTrainingDataGenerator.swift
git commit -m "feat: wire TrainingConfiguration through training pipeline

- TrainingCoordinator accepts configuration parameter
- ModelTrainer uses tree parameters from configuration
- BinaryTrainingDataGenerator uses sample thresholds from configuration
- All components use .default when not specified"
```

---

## Phase 3: Archive Old Plans

### Task 3.1: Archive Native Swift Implementation Plan

**Files:**
- Modify: `docs/plans/2026-01-11-native-swift-implementation-plan.md`

**Step 1: Add completion header to the file**

Add at the top of the file:

```markdown
---
status: COMPLETED
completed_date: 2026-01-28
notes: Native Swift implementation is complete. This plan is archived for historical reference.
---

```

**Step 2: Commit**

```bash
git add docs/plans/2026-01-11-native-swift-implementation-plan.md
git commit -m "docs: archive native-swift-implementation-plan as completed

The Swift rewrite is complete; this plan is now historical reference."
```

---

## Phase 4: Final Cleanup

### Task 4.1: Run Full Test Suite

**Step 1: Run all CrateBotCore tests**

```bash
cd CrateBotCore && swift test
```

Expected: All tests pass

**Step 2: Build the app**

```bash
xcodebuild -project CrateBot.xcodeproj -scheme CrateBot -configuration Debug build
```

Expected: Build succeeds

### Task 4.2: Create Summary Commit

**Step 1: Review all changes**

```bash
git log --oneline -10
git diff HEAD~10..HEAD --stat
```

**Step 2: Tag the cleanup milestone**

```bash
git tag -a v5.1.0-python-removal -m "Remove Python pipeline references, improve Swift training

Documentation:
- Rewrote SWIFT-TRAINING-PIPELINE.md as Swift-only docs
- Rewrote README.md to remove Python references
- Updated hook detection docs with Swift examples
- Archived completed implementation plan

Code improvements:
- Configurable tag groups in TagGroupRegistry
- Feature dimension validation in TrainingDataCollector
- Per-item progress reporting
- TrainingConfiguration for customizable parameters"
```

---

## Execution Checklist

| Phase | Task | Status |
|-------|------|--------|
| 1 | Rewrite SWIFT-TRAINING-PIPELINE.md | ⬜ |
| 1 | Rewrite README.md | ⬜ |
| 1 | Update LYRICS-FIRST-HOOK-DETECTION.md | ⬜ |
| 1 | Update Swift code comments | ⬜ |
| 2 | Add configurable TagGroupRegistry | ⬜ |
| 2 | Add feature dimension validation | ⬜ |
| 2 | Add per-item training progress | ⬜ |
| 2 | Create TrainingConfiguration | ⬜ |
| 2 | Wire configuration into pipeline | ⬜ |
| 3 | Archive old implementation plan | ⬜ |
| 4 | Run full test suite | ⬜ |
| 4 | Tag release | ⬜ |

---

## Future Work (Not In This Plan)

These items require more extensive changes and should be separate plans:

1. **Port VibeGenerator to native Swift** - Remove HTTPClient dependency, call Anthropic API directly
2. **Integrate WhisperKit for native hook detection** - Remove Whisper backend dependency
3. **Delete `backend/` and `python/` directories** - After above migrations complete
4. **Add training log export** - Export per-tag accuracy, skip reasons, contrastive loss
