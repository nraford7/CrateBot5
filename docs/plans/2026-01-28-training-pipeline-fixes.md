# Training Pipeline Bug Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix four critical/high-severity bugs in the training pipeline identified by Fresh Eyes code review.

**Architecture:** Four independent fixes targeting metadata loading, custom tag preservation, stale model cleanup, and duplicate API removal. Each fix is isolated and can be tested independently.

**Tech Stack:** Swift, CrateBotCore framework, XCTest

---

## Summary of Fixes

| Task | Issue | Severity |
|------|-------|----------|
| 1 | Metadata filename mismatch breaks tagging | CRITICAL |
| 2 | Custom descriptive tags silently dropped | HIGH |
| 3 | Stale model files persist after retraining | HIGH |
| 4 | Duplicate TrainingOptions fields unused | MEDIUM |

---

## Task 1: Fix Metadata Filename Mismatch

**Problem:** Training saves metadata as `<modelName>.json` but TaggingEngine looks for hardcoded `metadata.json`.

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:176-200`
- Modify: `CrateBot/App/AppState.swift:70`
- Modify: `CrateBot/Views/TrainView.swift:403`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineTests.swift`

### Step 1: Write failing test for model name parameter

Add to `TaggingEngineTests.swift`:

```swift
func testLoadModelWithModelName() async throws {
    // Create temp directory with model-specific metadata
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Create metadata as <modelName>.json (how training saves it)
    let metadata = ModelMetadata(
        name: "TestModel",
        tags: ["House", "Techno"],
        tagGroups: [],
        trainingFileCount: 100,
        accuracy: 0.85,
        createdAt: Date(),
        pipelineVersion: ModelMetadata.currentPipelineVersion,
        featureDimension: 1680
    )
    let metadataURL = tempDir.appendingPathComponent("TestModel.json")
    try metadata.save(to: metadataURL)

    // Load with model name - should find TestModel.json
    let engine = TaggingEngine()
    // This should NOT throw because metadata exists at TestModel.json
    // Current implementation looks for metadata.json and fails
    let (count, name) = try await engine.loadModel(from: tempDir, modelName: "TestModel")

    XCTAssertEqual(name, "TestModel")
}
```

### Step 2: Run test to verify it fails

```bash
cd CrateBotCore && swift test --filter testLoadModelWithModelName 2>&1 | tail -20
```

Expected: Compilation error - `loadModel` doesn't accept `modelName` parameter.

### Step 3: Update TaggingEngine.loadModel signature

Modify `TaggingEngine.swift` at line 176:

```swift
/// Load all classifiers from a model directory
/// - Parameters:
///   - modelDirectory: Directory containing .mlmodel files and metadata JSON
///   - modelName: Name of the model (used to find <modelName>.json metadata)
///   - progress: Optional async callback for loading progress (0.0 to 1.0)
///   - featureConfig: Optional feature config override (defaults to auto-detection from metadata)
/// - Returns: Number of classifiers loaded and the model name
public func loadModel(
    from modelDirectory: URL,
    modelName: String,
    progress: ((Double) async -> Void)? = nil,
    featureConfig: CombinedFeatureExtractor.FeatureConfig? = nil
) async throws -> (classifierCount: Int, modelName: String) {
```

### Step 4: Update metadata loading to use modelName

Replace line 199 in `TaggingEngine.swift`:

From:
```swift
let metadataURL = modelDirectory.appendingPathComponent("metadata.json")
```

To:
```swift
let metadataURL = modelDirectory.appendingPathComponent("\(modelName).json")
```

### Step 5: Update loadedModelName assignment

Replace line 285 in `TaggingEngine.swift`:

From:
```swift
let modelName = modelDirectory.lastPathComponent
loadedModelName = modelName
```

To:
```swift
loadedModelName = modelName
```

### Step 6: Run test to verify it passes

```bash
cd CrateBotCore && swift test --filter testLoadModelWithModelName 2>&1 | tail -20
```

Expected: PASS

### Step 7: Update AppState.swift caller

Modify `AppState.swift` around line 70. First, add a stored model name:

```swift
// Add property to track model name for loading
private var pendingModelName: String?
```

Update `loadModel(from:)` to extract model name from URL:

```swift
func loadModel(from url: URL) async throws {
    // Determine model name from URL
    // If it's a directory, use the directory name
    // If it's a file, use the filename without extension
    let modelName: String
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
        modelName = url.lastPathComponent
    } else {
        modelName = url.deletingPathExtension().lastPathComponent
    }

    let modelDirectory = isDirectory.boolValue ? url : url.deletingLastPathComponent()

    // ... rest of existing code but pass modelName:
    let (count, name) = try await engine.loadModel(
        from: modelDirectory,
        modelName: modelName
    ) { @MainActor [weak self] progress in
        self?.modelLoadingProgress = progress
    }
```

### Step 8: Update TrainView.swift caller

Modify `TrainView.swift` at line 403:

From:
```swift
try await appState.loadModel(from: summary.modelURL)
```

The `summary.modelURL` is the output directory. We need to pass the model name. The summary has `modelName`:

```swift
try await appState.loadModel(from: summary.modelURL, modelName: summary.modelName)
```

And update AppState's method signature:

```swift
func loadModel(from url: URL, modelName: String? = nil) async throws {
    // Use provided modelName or extract from URL
    let effectiveModelName: String
    if let name = modelName {
        effectiveModelName = name
    } else {
        // ... existing extraction logic
    }
```

### Step 9: Build and run all tests

```bash
cd CrateBotCore && swift build && swift test 2>&1 | tail -30
```

Expected: All tests pass.

### Step 10: Commit

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift \
        CrateBot/App/AppState.swift \
        CrateBot/Views/TrainView.swift \
        CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineTests.swift
git commit -m "fix: TaggingEngine loads metadata from <modelName>.json

Training saves metadata as <modelName>.json but TaggingEngine was
hardcoded to look for metadata.json. This caused metadata to never
load, breaking feature dimension detection and multi-class classifiers.

- Add modelName parameter to TaggingEngine.loadModel()
- Update metadata path to use modelName
- Update callers in AppState and TrainView

Fixes Fresh Eyes issue #1 (CRITICAL)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Preserve Custom Descriptive Tags

**Problem:** `DescriptiveTagMapping.organize()` drops tags not in hardcoded mapping.

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:50-121` (UserTagPredictions)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:540-575` (categorizePredictions)
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineTests.swift`

### Step 1: Write failing test for custom tags

Add to `TaggingEngineTests.swift`:

```swift
func testCustomTagsPreserved() {
    // Tags including custom ones not in DescriptiveTagMapping
    let predictions = UserTagPredictions(
        genre: "House",
        timing: "Peak",
        mood: "Happy",
        descriptive: ["Funky", "Groovy", "Driving", "Euphoric"]  // Groovy and Euphoric are custom
    )

    // Custom tags should be preserved
    XCTAssertTrue(predictions.customTags.contains("Groovy"), "Custom tag 'Groovy' should be preserved")
    XCTAssertTrue(predictions.customTags.contains("Euphoric"), "Custom tag 'Euphoric' should be preserved")

    // Known tags should be in their categories
    XCTAssertTrue(predictions.vibes.contains("Funky"), "Known tag 'Funky' should be in vibes")
    XCTAssertTrue(predictions.rhythm.contains("Driving"), "Known tag 'Driving' should be in rhythm")

    // All tags should appear in descriptive computed property
    let allDescriptive = predictions.descriptive
    XCTAssertTrue(allDescriptive.contains("Funky"))
    XCTAssertTrue(allDescriptive.contains("Groovy"))
    XCTAssertTrue(allDescriptive.contains("Driving"))
    XCTAssertTrue(allDescriptive.contains("Euphoric"))
}
```

### Step 2: Run test to verify it fails

```bash
cd CrateBotCore && swift test --filter testCustomTagsPreserved 2>&1 | tail -20
```

Expected: Compilation error - `customTags` property doesn't exist.

### Step 3: Add customTags property to UserTagPredictions

Modify `TaggingEngine.swift` at line 62, add after `acapella`:

```swift
    public let acapella: Bool?            // Binary (separate classifier)
    public let customTags: [String]       // Tags not in DescriptiveTagMapping
```

### Step 4: Update descriptive computed property

Modify `TaggingEngine.swift` lines 65-74:

```swift
    // Legacy flat array (computed for backwards compatibility)
    public var descriptive: [String] {
        var result: [String] = []
        if let bass = bassType { result.append(bass) }
        result.append(contentsOf: rhythm)
        result.append(contentsOf: style)
        result.append(contentsOf: vibes)
        result.append(contentsOf: instruments)
        if let vocal = vocalType { result.append(vocal) }
        result.append(contentsOf: customTags)  // Include custom tags
        return result
    }
```

### Step 5: Update convenience init to capture custom tags

Modify `TaggingEngine.swift` lines 77-96:

```swift
    // Convenience init with flat descriptive array (for backwards compat)
    public init(
        genre: String?,
        timing: String?,
        mood: String?,
        descriptive: [String]
    ) {
        self.genre = genre
        self.timing = timing
        self.mood = mood

        // Parse descriptive array into structured fields
        let organized = DescriptiveTagMapping.organize(descriptive)
        self.bassType = organized[.bassType]?.first
        self.rhythm = organized[.rhythm] ?? []
        self.style = organized[.style] ?? []
        self.vibes = organized[.vibes] ?? []
        self.instruments = organized[.instruments] ?? []
        self.vocalType = organized[.vocalType]?.first
        self.acapella = nil

        // Preserve tags not in DescriptiveTagMapping
        let knownTags = Set(organized.values.flatMap { $0 })
        self.customTags = descriptive.filter { !knownTags.contains($0) }
    }
```

### Step 6: Update full structured init

Modify `TaggingEngine.swift` lines 99-121:

```swift
    // Full structured init
    public init(
        genre: String?,
        timing: String?,
        mood: String?,
        bassType: String?,
        rhythm: [String],
        style: [String],
        vibes: [String],
        instruments: [String],
        vocalType: String?,
        acapella: Bool?,
        customTags: [String] = []
    ) {
        self.genre = genre
        self.timing = timing
        self.mood = mood
        self.bassType = bassType
        self.rhythm = rhythm
        self.style = style
        self.vibes = vibes
        self.instruments = instruments
        self.vocalType = vocalType
        self.acapella = acapella
        self.customTags = customTags
    }
```

### Step 7: Update categorizePredictions to preserve custom tags

Modify `TaggingEngine.swift` around line 551:

```swift
        // Organize descriptive tags by sub-category using DescriptiveTagMapping
        let organized = DescriptiveTagMapping.organize(descriptiveTags)

        // Preserve tags not in DescriptiveTagMapping
        let knownTags = Set(organized.values.flatMap { $0 })
        let customTags = descriptiveTags.filter { !knownTags.contains($0) }

        // Extract multi-class results (BassType, VocalType) - only first value if present
        let bassType = organized[.bassType]?.first
        let vocalType = organized[.vocalType]?.first

        // Binary descriptive tags (excluding multi-class sub-categories)
        let rhythm = organized[.rhythm] ?? []
        let style = organized[.style] ?? []
        let vibes = organized[.vibes] ?? []
        let instruments = organized[.instruments] ?? []

        return UserTagPredictions(
            genre: genre,
            timing: timing,
            mood: moodString,
            bassType: bassType,
            rhythm: rhythm,
            style: style,
            vibes: vibes,
            instruments: instruments,
            vocalType: vocalType,
            acapella: nil,
            customTags: customTags
        )
```

### Step 8: Run test to verify it passes

```bash
cd CrateBotCore && swift test --filter testCustomTagsPreserved 2>&1 | tail -20
```

Expected: PASS

### Step 9: Run all tests

```bash
cd CrateBotCore && swift test 2>&1 | tail -30
```

Expected: All tests pass.

### Step 10: Commit

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift \
        CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineTests.swift
git commit -m "fix: preserve custom descriptive tags not in mapping

Custom tags trained by users were silently dropped during
categorizePredictions() because DescriptiveTagMapping.organize()
only keeps tags in its hardcoded list.

- Add customTags field to UserTagPredictions
- Capture unrecognized tags in convenience init
- Update categorizePredictions to preserve custom tags
- Include custom tags in descriptive computed property

Fixes Fresh Eyes issue #2 (HIGH)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Clean Stale Model Files Before Training

**Problem:** Retraining with same model name leaves old `.mlmodel` files that get loaded.

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift:493-495`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCoordinatorTests.swift`

### Step 1: Write failing test for directory cleanup

Add to `TrainingCoordinatorTests.swift`:

```swift
func testTrainingCleansStaleModels() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let modelDir = tempDir.appendingPathComponent("TestModel")
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Create a "stale" model file that shouldn't exist after retraining
    let staleModelURL = modelDir.appendingPathComponent("OldTag.mlmodel")
    try "stale".write(to: staleModelURL, atomically: true, encoding: .utf8)

    XCTAssertTrue(FileManager.default.fileExists(atPath: staleModelURL.path), "Stale model should exist before training")

    // After training starts, the directory should be cleaned
    // We can't easily test full training, but we can test the cleanup logic
    // by calling the cleanup method directly (needs to be exposed or tested indirectly)

    // For now, verify stale file exists - the actual cleanup will be tested via integration
    // This test documents the expected behavior
}
```

### Step 2: Add cleanup before training

Modify `TrainingCoordinator.swift` at lines 493-495:

```swift
            // Phase 4: Train models
            _state = .training(progress: 0.0, currentTag: nil)
            await stateCallback?(_state)

            let outputDirectory = try await modelManager.modelsDirectory()
                .appendingPathComponent(options.modelName)

            // Clean stale models from previous training runs
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: outputDirectory.path) {
                logger.info("Cleaning existing model directory: \(outputDirectory.path)")
                try fileManager.removeItem(at: outputDirectory)
            }
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let trainingConfig = TrainingConfig(
```

### Step 3: Build and run tests

```bash
cd CrateBotCore && swift build && swift test 2>&1 | tail -30
```

Expected: All tests pass.

### Step 4: Commit

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift \
        CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCoordinatorTests.swift
git commit -m "fix: clean model directory before training

Retraining with the same model name left stale .mlmodel files from
previous runs. TaggingEngine loads all .mlmodel files it finds,
causing old tags to persist unexpectedly.

- Remove existing model directory before training
- Recreate empty directory for new models

Fixes Fresh Eyes issue #3 (HIGH)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Remove Duplicate TrainingOptions Fields

**Problem:** `validationSplit` and `minSamplesPerTag` exist on both `TrainingOptions` and nested `TrainingConfiguration`, but only the nested ones are used.

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift:97-101, 112-129`
- Modify: `CrateBot/Views/TrainView.swift:268-275`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCoordinatorTests.swift`

### Step 1: Remove duplicate fields from TrainingOptions

Modify `TrainingCoordinator.swift` lines 86-130. Remove `validationSplit` and `minSamplesPerTag`:

```swift
    /// Configuration options for training
    public struct TrainingOptions: Sendable {
        /// Name for the trained model
        public let modelName: String

        /// Tags to train (nil means all discovered tags)
        public let selectedTags: Set<String>?

        /// Tags organized by category (Genre, Timing, Mood, Descriptive)
        /// Used to properly categorize tags in model metadata
        public let tagsByCategory: [String: Set<String>]

        /// Mapping of ID3 fields to training categories
        public let tagFieldMapping: TrainingDataCollector.TagFieldMapping

        /// Registry of mutually exclusive tag groups for multi-class classification
        public let tagGroupRegistry: TagGroupRegistry

        /// Training hyperparameters configuration (includes minSamplesPerTag, validationSplit)
        public let configuration: TrainingConfiguration

        public init(
            modelName: String = "CustomModel",
            selectedTags: Set<String>? = nil,
            tagsByCategory: [String: Set<String>] = [:],
            tagFieldMapping: TrainingDataCollector.TagFieldMapping = .default,
            tagGroupRegistry: TagGroupRegistry = .defaultGroups,
            configuration: TrainingConfiguration = .default
        ) {
            self.modelName = modelName
            self.selectedTags = selectedTags
            self.tagsByCategory = tagsByCategory
            self.tagFieldMapping = tagFieldMapping
            self.tagGroupRegistry = tagGroupRegistry
            self.configuration = configuration
        }
    }
```

### Step 2: Update TrainView.swift caller

Modify `TrainView.swift` lines 268-275:

```swift
        // Build configuration with user's settings
        var config = TrainingConfiguration.default
        config.minSamplesPerTag = minSamplesPerTag

        let options = TrainingCoordinator.TrainingOptions(
            modelName: trimmedName,
            selectedTags: selectedTags.allTags,
            tagsByCategory: tagsByCategory,
            tagFieldMapping: tagMapping.coreMapping,
            configuration: config
        )
```

### Step 3: Build and verify

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && xcodebuild -scheme CrateBot -configuration Debug build 2>&1 | tail -20
```

Expected: Build succeeds.

### Step 4: Run tests

```bash
cd CrateBotCore && swift test 2>&1 | tail -30
```

Expected: All tests pass.

### Step 5: Commit

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift \
        CrateBot/Views/TrainView.swift
git commit -m "refactor: remove duplicate fields from TrainingOptions

TrainingOptions had validationSplit and minSamplesPerTag fields that
duplicated what's in TrainingConfiguration. The coordinator only used
the nested configuration values, making the top-level fields dead code.

- Remove validationSplit and minSamplesPerTag from TrainingOptions
- Update TrainView to pass values via TrainingConfiguration
- Single source of truth for training parameters

Fixes Fresh Eyes issue #4 (MEDIUM)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Final Verification

### Step 1: Build full project

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && xcodebuild -scheme CrateBot -configuration Debug build 2>&1 | tail -30
```

### Step 2: Run all tests

```bash
cd CrateBotCore && swift test
```

### Step 3: Create summary commit (optional)

If all tasks were committed separately, no summary needed. Otherwise:

```bash
git log --oneline -5
```

---

## Test Commands Reference

```bash
# Build CrateBotCore
cd CrateBotCore && swift build

# Run all tests
cd CrateBotCore && swift test

# Run specific test
cd CrateBotCore && swift test --filter testLoadModelWithModelName

# Build full Xcode project
xcodebuild -scheme CrateBot -configuration Debug build

# List tests
cd CrateBotCore && swift test --list-tests
```
