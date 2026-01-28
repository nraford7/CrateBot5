# Training Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve model accuracy through two complementary approaches: (1) richer feature vectors by concatenating genre activations to EffNet embeddings, and (2) multi-class classification for mutually exclusive tag groups.

**Architecture:** Phase 1 extends feature vectors from 1280 to 1680 dimensions by including already-extracted genre activations. Phase 2 adds multi-class classification for tag groups where a track can only have one label (e.g., BassType: Walking/Rolling/Punchy). Phase 3 (optional) adds PANN embeddings for 3728-dim features.

**Tech Stack:** Swift, CoreML (MLBoostedTreeClassifier), CreateML TabularData, AVFoundation

---

## Overview

| Phase | Feature | Effort | Impact |
|-------|---------|--------|--------|
| 1 | Extended Embeddings (1680-dim) | Low | Medium - richer audio semantics |
| 2 | Multi-Class Tag Groups | Medium | High - hard negatives for exclusive tags |
| 3 | PANN Embeddings (3728-dim) | Medium | High - complementary audio features |

**Dependency:** Phase 2 builds on Phase 1 (multi-class classifiers use extended features). Phase 3 is independent and optional.

---

## Phase 1: Extended Embeddings (1280 + 400 = 1680 dimensions)

### Task 1: Update EmbeddingCache for Extended Features

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/EmbeddingCache.swift:34`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/EmbeddingCacheTests.swift`

**Step 1: Write the failing test**

```swift
// EmbeddingCacheTests.swift
import XCTest
@testable import CrateBotCore

final class EmbeddingCacheTests: XCTestCase {

    func testCacheStoresExtendedEmbeddings() async throws {
        let cache = EmbeddingCache(extractorVersion: "effnet-v2-extended")

        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID()).mp3")
        try "test".write(to: testURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testURL) }

        // Store 1680-dim embeddings (1280 + 400)
        let embeddings = [Float](repeating: 0.5, count: 1680)
        await cache.set(embeddings, for: testURL)

        let retrieved = await cache.get(for: testURL)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.count, 1680)
    }

    func testCacheInvalidatesOnVersionChange() async throws {
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID()).mp3")
        try "test".write(to: testURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testURL) }

        // Store with old version
        let cacheV1 = EmbeddingCache(extractorVersion: "effnet-v1")
        await cacheV1.set([Float](repeating: 0.5, count: 1280), for: testURL)
        await cacheV1.save()

        // Load with new version - should miss
        let cacheV2 = EmbeddingCache(extractorVersion: "effnet-v2-extended")
        let retrieved = await cacheV2.get(for: testURL)
        XCTAssertNil(retrieved, "Cache should invalidate on version change")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd CrateBotCore && swift test --filter EmbeddingCacheTests`
Expected: FAIL (test file doesn't exist)

**Step 3: Update default extractor version**

```swift
// EmbeddingCache.swift line 34 - update default version
public init(extractorVersion: String = "effnet-v2-extended") {
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter EmbeddingCacheTests`
Expected: PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/EmbeddingCache.swift
git add CrateBotCore/Tests/CrateBotCoreTests/ML/EmbeddingCacheTests.swift
git commit -m "$(cat <<'EOF'
feat(cache): update extractor version for extended embeddings

Bump version to effnet-v2-extended to invalidate cached 1280-dim
embeddings when switching to 1680-dim (with genre activations).

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Update TrainingDataCollector for Extended Features

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift:702-735`

**Step 1: Locate the extraction code**

Find the batch processing block around line 702.

**Step 2: Update to use extractWithGenres and concatenate**

```swift
// Around line 702 - in the batch processing block
let batchResults = await withTaskGroup(of: (Int, TaggedTrack, [Float]?).self) { group in
    for (localIndex, track) in batch.enumerated() {
        group.addTask { [audioAnalyzer, extractor] in
            let globalIndex = batchStart + localIndex
            do {
                let fileURL = URL(fileURLWithPath: track.id)
                let buffer = try await audioAnalyzer.loadAudio(
                    from: fileURL,
                    targetSampleRate: EffNetExtractor.targetSampleRate
                )
                // CHANGED: Use extractWithGenres and concatenate
                let (embeddings, genreActivations) = try await extractor.extractWithGenres(from: buffer)
                let features = embeddings + genreActivations  // 1280 + 400 = 1680
                return (globalIndex, track, features)
            } catch {
                return (globalIndex, track, nil)
            }
        }
    }
    // ... rest unchanged
}
```

**Step 3: Run existing tests**

Run: `swift test --filter TrainingDataCollector`
Expected: PASS

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift
git commit -m "$(cat <<'EOF'
feat(training): concatenate genre activations to embeddings

Use extractWithGenres() to include 400-dim genre activations in
training features. Total dimension: 1680 (1280 + 400).

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Update TaggingEngine for Extended Feature Inference

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift:187-263`

**Step 1: Locate analyze(url:) method**

Find around line 192 where embeddings are extracted.

**Step 2: Create extended features and use for classifiers**

```swift
// Around line 192 in analyze(url:)
// Extract EffNet embeddings and genre activations
let (embeddings, genreActivations) = try await effnetExtractor.extractWithGenres(from: buffer)

// Create extended features for user classifiers (1680-dim)
let extendedFeatures = embeddings + genreActivations

// ... later around line 217-237, change classifier prediction:
for classifier in userClassifiers {
    trainedTagNames.insert(classifier.tagName.lowercased())
    do {
        // CHANGED: Use extendedFeatures instead of embeddings
        let (_, confidence) = try classifier.predictWithConfidence(features: extendedFeatures)
        // ... rest unchanged
    }
}
```

**Step 3: Run tests**

Run: `swift test --filter TaggingEngine`
Expected: PASS

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift
git commit -m "$(cat <<'EOF'
feat(tagging): use extended features for classifier inference

Pass concatenated embeddings+genres (1680-dim) to user classifiers
during tagging, matching the extended training features.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Update ModelMetadata with featureDimension

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelManager.swift` (or wherever ModelMetadata is defined)
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift:556-577`

**Step 1: Find and read ModelMetadata definition**

Search for `struct ModelMetadata` in the codebase.

**Step 2: Add featureDimension field**

```swift
public struct ModelMetadata: Codable, Sendable {
    // ... existing fields
    public let featureDimension: Int  // NEW: 1280, 1680, or 3728

    public init(
        // ... existing params
        featureDimension: Int = 1280  // Default for backward compatibility
    ) {
        // ... existing assignments
        self.featureDimension = featureDimension
    }
}
```

**Step 3: Update TrainingCoordinator.createModelMetadata**

```swift
// Around line 556-577
public func createModelMetadata(
    name: String,
    tags: [String],
    trainingFileCount: Int,
    accuracy: Double,
    featureDimension: Int = 1680  // NEW parameter with extended default
) -> ModelMetadata {
    // ... add featureDimension to return
}
```

**Step 4: Update call in train() around line 485**

```swift
let metadata = createModelMetadata(
    name: options.modelName,
    tags: trainedTagNames,
    trainingFileCount: validTracks.count,
    accuracy: avgAccuracy,
    featureDimension: 1680  // Extended features
)
```

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/
git commit -m "$(cat <<'EOF'
feat(metadata): track feature dimension in model metadata

Add featureDimension field to ModelMetadata. New models record 1680
for extended features. Default 1280 for backward compatibility.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Build and Test Phase 1

**Step 1: Build the package**

```bash
cd CrateBotCore && swift build
```
Expected: Build succeeds

**Step 2: Run all tests**

```bash
swift test
```
Expected: All tests pass

**Step 3: Build the app**

```bash
cd .. && xcodebuild -scheme CrateBot -configuration Debug build
```
Expected: Build succeeds

**Step 4: Commit**

```bash
git add .
git commit -m "$(cat <<'EOF'
feat: complete Phase 1 - extended embeddings (1680-dim)

- EmbeddingCache: version bump invalidates old 1280-dim cache
- TrainingDataCollector: extracts 1680-dim features (embeddings + genres)
- TaggingEngine: passes extended features to classifiers
- ModelMetadata: tracks featureDimension

New models use 400 additional genre activation dimensions.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Multi-Class Tag Groups

### Task 6: Define TagGroupRegistry Data Model

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TagGroupRegistryTests.swift`

**Step 1: Write the failing test**

```swift
// TagGroupRegistryTests.swift
import XCTest
@testable import CrateBotCore

final class TagGroupRegistryTests: XCTestCase {

    func testCreateTagGroup() {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy"])

        XCTAssertEqual(registry.groups.count, 1)
        XCTAssertEqual(registry.groups["BassType"], ["Walking", "Rolling", "Punchy"])
    }

    func testFindGroupForTag() {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy"])
        registry.addGroup(name: "Rhythm", tags: ["FourOnFloor", "Breakbeat", "Halftime"])

        XCTAssertEqual(registry.groupName(for: "Walking"), "BassType")
        XCTAssertEqual(registry.groupName(for: "Breakbeat"), "Rhythm")
        XCTAssertNil(registry.groupName(for: "UnknownTag"))
    }

    func testNormalizeTagToClassName() {
        let registry = TagGroupRegistry()
        XCTAssertEqual(registry.normalizeTagToClass("WalkingBass", inGroup: "BassType"), "Walking")
    }

    func testPersistence() throws {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling"])

        let data = try JSONEncoder().encode(registry)
        let decoded = try JSONDecoder().decode(TagGroupRegistry.self, from: data)

        XCTAssertEqual(decoded.groups, registry.groups)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TagGroupRegistryTests`
Expected: FAIL

**Step 3: Write implementation**

```swift
// TagGroupRegistry.swift
import Foundation

/// Registry of mutually exclusive tag groups for multi-class classification
public struct TagGroupRegistry: Codable, Sendable, Equatable {

    /// Map of group name to array of class names within that group
    public var groups: [String: [String]] = [:]

    /// Reverse lookup: tag/class name → group name
    private var tagToGroup: [String: String] = [:]

    public init() {}

    public init(groups: [String: [String]]) {
        self.groups = groups
        rebuildTagToGroupMap()
    }

    public mutating func addGroup(name: String, tags: [String]) {
        groups[name] = tags
        for tag in tags {
            tagToGroup[tag.lowercased()] = name
        }
    }

    public mutating func removeGroup(name: String) {
        if let tags = groups[name] {
            for tag in tags {
                tagToGroup.removeValue(forKey: tag.lowercased())
            }
        }
        groups.removeValue(forKey: name)
    }

    public func groupName(for tag: String) -> String? {
        if let group = tagToGroup[tag.lowercased()] {
            return group
        }
        // Try suffix matching (e.g., "WalkingBass" → "Walking" in BassType)
        for (groupName, classes) in groups {
            for className in classes {
                if tag.lowercased().contains(className.lowercased()) {
                    return groupName
                }
            }
        }
        return nil
    }

    public func normalizeTagToClass(_ tag: String, inGroup groupName: String) -> String? {
        guard let classes = groups[groupName] else { return nil }
        let lowercasedTag = tag.lowercased()

        if let exactMatch = classes.first(where: { $0.lowercased() == lowercasedTag }) {
            return exactMatch
        }
        if let partialMatch = classes.first(where: { lowercasedTag.contains($0.lowercased()) }) {
            return partialMatch
        }
        return nil
    }

    public var groupedTags: Set<String> {
        Set(tagToGroup.keys)
    }

    public func isGrouped(_ tag: String) -> Bool {
        groupName(for: tag) != nil
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case groups
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decode([String: [String]].self, forKey: .groups)
        rebuildTagToGroupMap()
    }

    private mutating func rebuildTagToGroupMap() {
        tagToGroup = [:]
        for (groupName, tags) in groups {
            for tag in tags {
                tagToGroup[tag.lowercased()] = groupName
            }
        }
    }
}
```

**Step 4: Run test**

Run: `swift test --filter TagGroupRegistryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift
git add CrateBotCore/Tests/CrateBotCoreTests/ML/TagGroupRegistryTests.swift
git commit -m "$(cat <<'EOF'
feat: add TagGroupRegistry for multi-class tag groups

Data model for mutually exclusive tag groups (e.g., BassType with
Walking/Rolling/Punchy). Supports persistence and tag normalization.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Multi-Class Training Data Generator

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/MultiClassTrainingDataGenerator.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/MultiClassTrainingDataGeneratorTests.swift`

**Step 1: Write the failing test**

```swift
// MultiClassTrainingDataGeneratorTests.swift
import XCTest
@testable import CrateBotCore

final class MultiClassTrainingDataGeneratorTests: XCTestCase {

    func testGenerateMultiClassData() {
        let tracks = [
            TaggedTrack(id: "track1", tags: ["WalkingBass", "House"], features: [Float](repeating: 0.1, count: 1680)),
            TaggedTrack(id: "track2", tags: ["RollingBass", "Techno"], features: [Float](repeating: 0.2, count: 1680)),
            TaggedTrack(id: "track3", tags: ["WalkingBass", "Disco"], features: [Float](repeating: 0.3, count: 1680)),
            TaggedTrack(id: "track4", tags: ["PunchyBass", "House"], features: [Float](repeating: 0.4, count: 1680)),
            TaggedTrack(id: "track5", tags: ["Deep"], features: [Float](repeating: 0.5, count: 1680)),
        ]

        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy"])

        let generator = MultiClassTrainingDataGenerator(registry: registry)
        let result = generator.generateTrainingData(for: "BassType", from: tracks, minSamplesPerClass: 1)

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.samples.count, 4)

        let walkingCount = result!.samples.filter { $0.className == "Walking" }.count
        XCTAssertEqual(walkingCount, 2)
    }

    func testMinSamplesRequirement() {
        let tracks = [
            TaggedTrack(id: "track1", tags: ["WalkingBass"], features: [Float](repeating: 0.1, count: 1680)),
        ]

        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling"])

        let generator = MultiClassTrainingDataGenerator(registry: registry)
        let result = generator.generateTrainingData(for: "BassType", from: tracks, minSamplesPerClass: 10)

        XCTAssertNil(result)
    }
}
```

**Step 2: Run test**

**Step 3: Write implementation**

```swift
// MultiClassTrainingDataGenerator.swift
import Foundation

public final class MultiClassTrainingDataGenerator: Sendable {

    public struct ClassifiedSample: Sendable {
        public let trackId: String
        public let className: String
        public let features: [Float]
    }

    public struct MultiClassTrainingData: Sendable {
        public let groupName: String
        public let classes: [String]
        public let samples: [ClassifiedSample]

        public var classCounts: [String: Int] {
            var counts: [String: Int] = [:]
            for sample in samples {
                counts[sample.className, default: 0] += 1
            }
            return counts
        }
    }

    private let registry: TagGroupRegistry

    public init(registry: TagGroupRegistry) {
        self.registry = registry
    }

    public func generateTrainingData(
        for groupName: String,
        from tracks: [TaggedTrack],
        minSamplesPerClass: Int = 10
    ) -> MultiClassTrainingData? {

        guard let classes = registry.groups[groupName] else { return nil }

        var samples: [ClassifiedSample] = []
        var classCounts: [String: Int] = [:]

        for track in tracks {
            guard let features = track.features else { continue }

            var assignedClass: String?
            for tag in track.tags {
                if let className = registry.normalizeTagToClass(tag, inGroup: groupName) {
                    assignedClass = className
                    break
                }
            }

            guard let className = assignedClass else { continue }

            samples.append(ClassifiedSample(trackId: track.id, className: className, features: features))
            classCounts[className, default: 0] += 1
        }

        let validClasses = classes.filter { (classCounts[$0] ?? 0) >= minSamplesPerClass }

        if validClasses.count < 2 {
            return nil
        }

        let validSamples = samples.filter { validClasses.contains($0.className) }

        return MultiClassTrainingData(groupName: groupName, classes: validClasses.sorted(), samples: validSamples)
    }

    public func viableGroups(from tracks: [TaggedTrack], minSamplesPerClass: Int = 10, minClasses: Int = 2) -> [String] {
        var viable: [String] = []
        for groupName in registry.groups.keys {
            if let data = generateTrainingData(for: groupName, from: tracks, minSamplesPerClass: minSamplesPerClass) {
                if data.classes.count >= minClasses {
                    viable.append(groupName)
                }
            }
        }
        return viable.sorted()
    }
}
```

**Step 4: Run test**

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/MultiClassTrainingDataGenerator.swift
git add CrateBotCore/Tests/CrateBotCoreTests/ML/MultiClassTrainingDataGeneratorTests.swift
git commit -m "$(cat <<'EOF'
feat: add MultiClassTrainingDataGenerator for grouped tags

Generates training data for multi-class classification. Maps tags
like "WalkingBass" to class "Walking" in group "BassType".

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Add Multi-Class Training to ModelTrainer

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelTrainerMultiClassTests.swift`

**Step 1: Write the failing test**

```swift
// ModelTrainerMultiClassTests.swift
import XCTest
@testable import CrateBotCore

final class ModelTrainerMultiClassTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testTrainMultiClassModel() async throws {
        let samplesPerClass = 60
        var samples: [MultiClassTrainingDataGenerator.ClassifiedSample] = []

        for i in 0..<samplesPerClass {
            samples.append(.init(trackId: "a_\(i)", className: "ClassA",
                features: (0..<1680).map { _ in Float.random(in: 0.1...0.3) }))
            samples.append(.init(trackId: "b_\(i)", className: "ClassB",
                features: (0..<1680).map { _ in Float.random(in: 0.4...0.6) }))
            samples.append(.init(trackId: "c_\(i)", className: "ClassC",
                features: (0..<1680).map { _ in Float.random(in: 0.7...0.9) }))
        }

        let trainingData = MultiClassTrainingDataGenerator.MultiClassTrainingData(
            groupName: "TestGroup", classes: ["ClassA", "ClassB", "ClassC"], samples: samples)

        let trainer = ModelTrainer()
        let result = try await trainer.trainMultiClassModel(data: trainingData, outputDirectory: tempDir)

        XCTAssertEqual(result.groupName, "TestGroup")
        XCTAssertEqual(result.classes.count, 3)
        XCTAssertGreaterThan(result.accuracy, 0.7)

        let modelPath = tempDir.appendingPathComponent("TestGroup.mlmodel")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelPath.path))
    }
}
```

**Step 2: Run test**

**Step 3: Add trainMultiClassModel to ModelTrainer**

```swift
// Add to ModelTrainer.swift

// MARK: - Multi-Class Training

public struct MultiClassTrainingResult: Sendable {
    public let groupName: String
    public let classes: [String]
    public let accuracy: Double
    public let perClassAccuracy: [String: Double]
    public let modelURL: URL
}

public func trainMultiClassModel(
    data: MultiClassTrainingDataGenerator.MultiClassTrainingData,
    outputDirectory: URL,
    validationSplit: Double = 0.2
) async throws -> MultiClassTrainingResult {

    let groupName = data.groupName
    let classes = data.classes
    let featureCount = data.samples.first?.features.count ?? 1680

    logger.info("Training multi-class model for '\(groupName)' with \(classes.count) classes")

    let shuffled = data.samples.shuffled()
    let splitIndex = Int(Double(shuffled.count) * (1.0 - validationSplit))
    let trainingSamples = Array(shuffled[..<splitIndex])
    let validationSamples = Array(shuffled[splitIndex...])

    // Build DataFrame
    let dataFrame = try prepareMultiClassDataFrame(samples: trainingSamples, featureCount: featureCount)

    // Train multi-class boosted tree
    let classifier = try MLBoostedTreeClassifier(
        trainingData: dataFrame,
        targetColumn: "label",
        parameters: MLBoostedTreeClassifier.ModelParameters(
            maxDepth: 6,
            maxIterations: 100,
            minLossReduction: 0.0,
            minChildWeight: 1.0,
            stepSize: 0.3
        )
    )

    // Validate
    let (accuracy, perClassAccuracy) = try calculateMultiClassAccuracy(
        classifier: classifier, samples: validationSamples, featureCount: featureCount)

    logger.info("'\(groupName)' validation accuracy: \(String(format: "%.1f%%", accuracy * 100))")

    // Save
    let modelURL = outputDirectory.appendingPathComponent("\(groupName).mlmodel")
    try classifier.write(to: modelURL, metadata: nil)

    return MultiClassTrainingResult(
        groupName: groupName, classes: classes, accuracy: accuracy,
        perClassAccuracy: perClassAccuracy, modelURL: modelURL)
}

private func prepareMultiClassDataFrame(
    samples: [MultiClassTrainingDataGenerator.ClassifiedSample],
    featureCount: Int
) throws -> DataFrame {
    var columns: [String: [Double]] = [:]
    for i in 0..<featureCount {
        columns["f\(i)"] = []
    }
    var labels: [String] = []

    for sample in samples {
        for (i, value) in sample.features.enumerated() where i < featureCount {
            columns["f\(i)"]?.append(Double(value))
        }
        labels.append(sample.className)
    }

    var dataFrame = DataFrame()
    for i in 0..<featureCount {
        if let values = columns["f\(i)"] {
            dataFrame.append(column: Column(name: "f\(i)", contents: values))
        }
    }
    dataFrame.append(column: Column(name: "label", contents: labels))

    return dataFrame
}

private func calculateMultiClassAccuracy(
    classifier: MLBoostedTreeClassifier,
    samples: [MultiClassTrainingDataGenerator.ClassifiedSample],
    featureCount: Int
) throws -> (Double, [String: Double]) {
    var correctCount = 0
    var perClassCorrect: [String: Int] = [:]
    var perClassTotal: [String: Int] = [:]

    for sample in samples {
        var featureDict: [String: MLFeatureValue] = [:]
        for (i, value) in sample.features.enumerated() where i < featureCount {
            featureDict["f\(i)"] = MLFeatureValue(double: Double(value))
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let prediction = try classifier.predictions(from: DataFrame()).first

        // Use model directly for single predictions
        let output = try classifier.model.prediction(from: provider)
        if let predictedLabel = output.featureValue(for: "label")?.stringValue {
            perClassTotal[sample.className, default: 0] += 1
            if predictedLabel == sample.className {
                correctCount += 1
                perClassCorrect[sample.className, default: 0] += 1
            }
        }
    }

    let accuracy = samples.isEmpty ? 0 : Double(correctCount) / Double(samples.count)

    var perClassAccuracy: [String: Double] = [:]
    for (className, total) in perClassTotal {
        let correct = perClassCorrect[className] ?? 0
        perClassAccuracy[className] = Double(correct) / Double(total)
    }

    return (accuracy, perClassAccuracy)
}
```

**Step 4: Run test**

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift
git add CrateBotCore/Tests/CrateBotCoreTests/ML/ModelTrainerMultiClassTests.swift
git commit -m "$(cat <<'EOF'
feat: add multi-class model training to ModelTrainer

Train MLBoostedTreeClassifier for multi-class groups. Reports overall
and per-class validation accuracy.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Create MultiClassClassifier for Inference

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/MultiClassClassifier.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/MultiClassClassifierTests.swift`

**Step 1: Write the failing test**

```swift
// MultiClassClassifierTests.swift
import XCTest
@testable import CrateBotCore

final class MultiClassClassifierTests: XCTestCase {

    func testPredictionDataStructure() {
        let probs: [String: Float] = ["ClassA": 0.7, "ClassB": 0.2, "ClassC": 0.1]
        let result = MultiClassClassifier.Prediction(
            predictedClass: "ClassA", confidence: 0.7, classProbabilities: probs)

        XCTAssertEqual(result.predictedClass, "ClassA")
        XCTAssertEqual(result.confidence, 0.7)
        XCTAssertEqual(result.classProbabilities.count, 3)
    }
}
```

**Step 2: Run test**

**Step 3: Write implementation**

```swift
// MultiClassClassifier.swift
import Foundation
import CoreML

public actor MultiClassClassifier {

    public struct Prediction: Sendable {
        public let predictedClass: String
        public let confidence: Float
        public let classProbabilities: [String: Float]
    }

    public let groupName: String
    public let classes: [String]
    public let featureCount: Int

    private let model: MLModel

    public init(groupName: String, classes: [String], modelURL: URL, featureCount: Int = 1680) throws {
        self.groupName = groupName
        self.classes = classes
        self.featureCount = featureCount

        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try MLModel.compileModel(at: modelURL)
        }
        self.model = try MLModel(contentsOf: compiledURL)
    }

    public func predict(features: [Float]) throws -> Prediction {
        guard features.count == featureCount else {
            throw ClassifierError.invalidFeatureCount(expected: featureCount, got: features.count)
        }

        var featureDict: [String: MLFeatureValue] = [:]
        for (i, value) in features.enumerated() {
            featureDict["f\(i)"] = MLFeatureValue(double: Double(value))
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let prediction = try model.prediction(from: provider)

        guard let predictedClass = prediction.featureValue(for: "label")?.stringValue else {
            throw ClassifierError.missingPrediction
        }

        var classProbabilities: [String: Float] = [:]
        if let probsDict = prediction.featureValue(for: "labelProbability")?.dictionaryValue {
            for (key, value) in probsDict {
                if let className = key as? String, let prob = value as? Double {
                    classProbabilities[className] = Float(prob)
                }
            }
        }

        let confidence = classProbabilities[predictedClass] ?? 0.0

        return Prediction(predictedClass: predictedClass, confidence: confidence, classProbabilities: classProbabilities)
    }

    public enum ClassifierError: Error, LocalizedError {
        case invalidFeatureCount(expected: Int, got: Int)
        case missingPrediction

        public var errorDescription: String? {
            switch self {
            case .invalidFeatureCount(let expected, let got):
                return "Invalid feature count: expected \(expected), got \(got)"
            case .missingPrediction:
                return "Model did not return a prediction"
            }
        }
    }
}
```

**Step 4: Run test**

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/MultiClassClassifier.swift
git add CrateBotCore/Tests/CrateBotCoreTests/ML/MultiClassClassifierTests.swift
git commit -m "$(cat <<'EOF'
feat: add MultiClassClassifier for grouped tag inference

Wraps CoreML model for multi-class prediction. Returns predicted class
with confidence and full probability distribution.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Update ModelMetadata for Tag Groups

**Files:**
- Modify: ModelMetadata definition (same file as Task 4)

**Step 1: Add TagGroupInfo struct and tagGroups field**

```swift
public struct TagGroupInfo: Codable, Sendable {
    public let groupName: String
    public let classes: [String]
    public let accuracy: Double
    public let perClassAccuracy: [String: Double]

    public init(groupName: String, classes: [String], accuracy: Double, perClassAccuracy: [String: Double]) {
        self.groupName = groupName
        self.classes = classes
        self.accuracy = accuracy
        self.perClassAccuracy = perClassAccuracy
    }
}

// Add to ModelMetadata:
public let tagGroups: [TagGroupInfo]  // Default to empty array for backward compat
```

**Step 2: Update createModelMetadata in TrainingCoordinator**

```swift
public func createModelMetadata(
    name: String,
    tags: [String],
    trainingFileCount: Int,
    accuracy: Double,
    featureDimension: Int = 1680,
    tagGroups: [TagGroupInfo] = []  // NEW
) -> ModelMetadata
```

**Step 3: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/
git commit -m "$(cat <<'EOF'
feat: add tag group info to ModelMetadata

Store trained multi-class group metadata including classes and
per-class accuracy. Enables TaggingEngine to load group classifiers.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Integrate Multi-Class into TrainingCoordinator

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`

**Step 1: Add tagGroupRegistry to TrainingOptions**

```swift
public struct TrainingOptions: Sendable {
    // ... existing fields
    public let tagGroupRegistry: TagGroupRegistry

    public init(
        // ... existing params
        tagGroupRegistry: TagGroupRegistry = TagGroupRegistry()
    ) {
        // ... existing assignments
        self.tagGroupRegistry = tagGroupRegistry
    }
}
```

**Step 2: Modify train() to handle both binary and multi-class**

After feature extraction, before binary training:

```swift
// Identify and train multi-class groups
let multiClassGenerator = MultiClassTrainingDataGenerator(registry: options.tagGroupRegistry)
let viableGroups = multiClassGenerator.viableGroups(from: validTracks, minSamplesPerClass: options.minSamplesPerTag)

var multiClassResults: [MultiClassTrainingResult] = []
var groupedTagNames: Set<String> = []

for groupName in viableGroups {
    if let groupData = multiClassGenerator.generateTrainingData(
        for: groupName, from: validTracks, minSamplesPerClass: options.minSamplesPerTag) {

        let result = try await modelTrainer.trainMultiClassModel(data: groupData, outputDirectory: outputDirectory)
        multiClassResults.append(result)

        // Track which tags are covered by groups
        for className in result.classes {
            groupedTagNames.insert(className.lowercased())
        }
    }
}

// Filter binary tags to exclude grouped ones
let binaryTags = viableTags.filter { !options.tagGroupRegistry.isGrouped($0) }

// Continue with binary training for binaryTags...
```

**Step 3: Update metadata creation**

```swift
let tagGroupInfos = multiClassResults.map { result in
    TagGroupInfo(groupName: result.groupName, classes: result.classes,
                 accuracy: result.accuracy, perClassAccuracy: result.perClassAccuracy)
}

let metadata = createModelMetadata(
    name: options.modelName,
    tags: trainedTagNames,
    trainingFileCount: validTracks.count,
    accuracy: avgAccuracy,
    featureDimension: 1680,
    tagGroups: tagGroupInfos
)
```

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift
git commit -m "$(cat <<'EOF'
feat: integrate multi-class training into TrainingCoordinator

Train multi-class models for viable groups, then binary classifiers
for remaining tags. Records group info in metadata.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Update TaggingEngine for Multi-Class Inference

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

**Step 1: Add multi-class classifier storage**

```swift
private var multiClassClassifiers: [String: MultiClassClassifier] = [:]
```

**Step 2: Load multi-class models in loadModel()**

After loading binary classifiers:

```swift
// Load multi-class classifiers
if let metadataURL = modelDirectory.appendingPathComponent("\(modelName).json") as URL?,
   let metadata = try? ModelMetadata.load(from: metadataURL) {
    for groupInfo in metadata.tagGroups {
        let modelURL = modelDirectory.appendingPathComponent("\(groupInfo.groupName).mlmodel")
        if FileManager.default.fileExists(atPath: modelURL.path) {
            do {
                let classifier = try MultiClassClassifier(
                    groupName: groupInfo.groupName,
                    classes: groupInfo.classes,
                    modelURL: modelURL,
                    featureCount: metadata.featureDimension
                )
                multiClassClassifiers[groupInfo.groupName] = classifier
            } catch {
                print("Failed to load multi-class classifier '\(groupInfo.groupName)': \(error)")
            }
        }
    }
}
```

**Step 3: Run multi-class predictions in analyze()**

After extracting features:

```swift
// Run multi-class classifiers
var groupPredictions: [(groupName: String, predictedClass: String, confidence: Float)] = []

for (groupName, classifier) in multiClassClassifiers {
    do {
        let prediction = try await classifier.predict(features: extendedFeatures)
        if prediction.confidence >= classificationThreshold {
            groupPredictions.append((groupName, prediction.predictedClass, prediction.confidence))
            predictedTags.append(prediction.predictedClass)
        }
    } catch {
        print("Multi-class classifier '\(groupName)' failed: \(error)")
    }
}
```

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift
git commit -m "$(cat <<'EOF'
feat: add multi-class inference to TaggingEngine

Load and run multi-class classifiers alongside binary classifiers.
Returns winning class per group when confidence meets threshold.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: UI for Defining Tag Groups

**Files:**
- Create: `CrateBot/Views/TagGroupsEditor.swift`
- Modify: `CrateBot/Views/SettingsPanel.swift`
- Modify: `CrateBot/App/AppState.swift`

**Step 1: Create TagGroupsEditor view**

```swift
// TagGroupsEditor.swift
import SwiftUI
import CrateBotCore

struct TagGroupsEditor: View {
    @Binding var registry: TagGroupRegistry
    @State private var showAddGroup = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Tag Groups")
                    .font(Theme.Fonts.heading(16))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Button {
                    showAddGroup = true
                } label: {
                    Label("Add Group", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Text("Tags within a group are mutually exclusive")
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textSecondary)

            ForEach(Array(registry.groups.keys.sorted()), id: \.self) { groupName in
                TagGroupRow(
                    groupName: groupName,
                    tags: registry.groups[groupName] ?? [],
                    onDelete: { registry.removeGroup(name: groupName) }
                )
            }

            if registry.groups.isEmpty {
                Text("No tag groups defined")
                    .font(Theme.Fonts.body(13))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding()
            }
        }
        .sheet(isPresented: $showAddGroup) {
            AddTagGroupSheet(registry: $registry)
        }
    }
}

struct TagGroupRow: View {
    let groupName: String
    let tags: [String]
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(groupName)
                    .font(Theme.Fonts.label(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(tags.joined(separator: ", "))
                    .font(Theme.Fonts.mono(11))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(Theme.Colors.statusError)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.bgSurface)
        .cornerRadius(Theme.Radius.sm)
    }
}

struct AddTagGroupSheet: View {
    @Binding var registry: TagGroupRegistry
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var tagsText = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Add Tag Group")
                .font(Theme.Fonts.heading(18))

            TextField("Group Name (e.g., BassType)", text: $groupName)
                .textFieldStyle(.roundedBorder)

            TextField("Tags (comma-separated)", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            Text("Example: Walking, Rolling, Punchy, Deep")
                .font(Theme.Fonts.body(11))
                .foregroundColor(Theme.Colors.textTertiary)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Add") {
                    let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    if !groupName.isEmpty && tags.count >= 2 {
                        registry.addGroup(name: groupName, tags: tags)
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(groupName.isEmpty || tagsText.isEmpty)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 400)
    }
}
```

**Step 2: Add to AppState**

```swift
// In AppState
var tagGroupRegistry: TagGroupRegistry = TagGroupRegistry() {
    didSet { saveTagGroupRegistry() }
}

private func saveTagGroupRegistry() {
    // Save to UserDefaults or file
    if let data = try? JSONEncoder().encode(tagGroupRegistry) {
        UserDefaults.standard.set(data, forKey: "tagGroupRegistry")
    }
}

private func loadTagGroupRegistry() {
    if let data = UserDefaults.standard.data(forKey: "tagGroupRegistry"),
       let registry = try? JSONDecoder().decode(TagGroupRegistry.self, from: data) {
        tagGroupRegistry = registry
    }
}
```

**Step 3: Add to SettingsPanel**

Add a section for tag groups.

**Step 4: Commit**

```bash
git add CrateBot/Views/TagGroupsEditor.swift
git add CrateBot/Views/SettingsPanel.swift
git add CrateBot/App/AppState.swift
git commit -m "$(cat <<'EOF'
feat: add UI for defining tag groups

TagGroupsEditor allows users to create/delete mutually exclusive
tag groups. Persisted in AppState via UserDefaults.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Pass Tag Groups to Training

**Files:**
- Modify: `CrateBot/Views/TrainView.swift`

**Step 1: Include tag group registry in training options**

```swift
let options = TrainingCoordinator.TrainingOptions(
    modelName: trimmedName,
    selectedTags: selectedTags.allTags,
    validationSplit: 0.2,
    minSamplesPerTag: minSamplesPerTag,
    tagFieldMapping: tagMapping.coreMapping,
    tagGroupRegistry: appState.tagGroupRegistry  // NEW
)
```

**Step 2: Show multi-class results in training summary**

Update completion UI to display which groups were trained.

**Step 3: Commit**

```bash
git add CrateBot/Views/TrainView.swift
git commit -m "$(cat <<'EOF'
feat: pass tag groups to training and show results

TrainView passes tagGroupRegistry to TrainingCoordinator and displays
multi-class group results in the completion summary.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Integration Tests

**Files:**
- Create: `CrateBotCore/Tests/CrateBotCoreTests/Integration/TrainingImprovementsIntegrationTests.swift`

**Step 1: Write end-to-end tests**

```swift
// TrainingImprovementsIntegrationTests.swift
import XCTest
@testable import CrateBotCore

final class TrainingImprovementsIntegrationTests: XCTestCase {

    func testExtendedFeatureDimensions() async throws {
        let extractor = try EffNetExtractor()
        // Verify we can get both embeddings and genres
        XCTAssertEqual(extractor.featureCount, 1280)
        // Total with genres: 1280 + 400 = 1680
    }

    func testMultiClassTrainingFlow() async throws {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "TestBass", tags: ["Walking", "Rolling", "Punchy"])

        // Create synthetic training data
        var tracks: [TaggedTrack] = []
        for i in 0..<60 {
            tracks.append(TaggedTrack(id: "walk_\(i)", tags: Set(["WalkingBass"]),
                features: (0..<1680).map { _ in Float.random(in: 0.1...0.3) }))
            tracks.append(TaggedTrack(id: "roll_\(i)", tags: Set(["RollingBass"]),
                features: (0..<1680).map { _ in Float.random(in: 0.4...0.6) }))
            tracks.append(TaggedTrack(id: "punch_\(i)", tags: Set(["PunchyBass"]),
                features: (0..<1680).map { _ in Float.random(in: 0.7...0.9) }))
        }

        let generator = MultiClassTrainingDataGenerator(registry: registry)
        let data = generator.generateTrainingData(for: "TestBass", from: tracks, minSamplesPerClass: 50)

        XCTAssertNotNil(data)
        XCTAssertEqual(data!.classes.count, 3)
        XCTAssertEqual(data!.samples.count, 180)
    }
}
```

**Step 2: Run tests**

```bash
swift test --filter TrainingImprovementsIntegrationTests
```

**Step 3: Commit**

```bash
git add CrateBotCore/Tests/CrateBotCoreTests/Integration/TrainingImprovementsIntegrationTests.swift
git commit -m "$(cat <<'EOF'
test: add training improvements integration tests

End-to-end tests for extended features and multi-class training flow.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: PANN Embeddings (Optional)

### Task 16-19: PANN Integration

See `docs/plans/2026-01-25-enhanced-embeddings.md` Tasks 6-9 for:
- Convert PANN model to CoreML (Python script)
- Create PANNExtractor
- Create CombinedFeatureExtractor
- Update TrainingCoordinator with feature configuration

**Note:** Phase 3 is independent and can be implemented after Phase 1 & 2 if additional accuracy is needed.

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| **Phase 1: Extended Embeddings** | | |
| 1 | Update EmbeddingCache version | EmbeddingCache.swift |
| 2 | Concatenate genres in TrainingDataCollector | TrainingDataCollector.swift |
| 3 | Use extended features in TaggingEngine | TaggingEngine.swift |
| 4 | Add featureDimension to ModelMetadata | ModelMetadata, TrainingCoordinator |
| 5 | Build and test Phase 1 | - |
| **Phase 2: Multi-Class Tag Groups** | | |
| 6 | TagGroupRegistry data model | TagGroupRegistry.swift |
| 7 | MultiClassTrainingDataGenerator | MultiClassTrainingDataGenerator.swift |
| 8 | Multi-class training in ModelTrainer | ModelTrainer.swift |
| 9 | MultiClassClassifier for inference | MultiClassClassifier.swift |
| 10 | Add tagGroups to ModelMetadata | ModelMetadata |
| 11 | Integrate into TrainingCoordinator | TrainingCoordinator.swift |
| 12 | Update TaggingEngine for multi-class | TaggingEngine.swift |
| 13 | UI for defining tag groups | TagGroupsEditor.swift, SettingsPanel, AppState |
| 14 | Pass tag groups to TrainView | TrainView.swift |
| 15 | Integration tests | Integration tests |
| **Phase 3: PANN (Optional)** | | |
| 16-19 | PANN model conversion and integration | PANNExtractor, CombinedFeatureExtractor |

**Key Benefits:**
1. **Phase 1:** +400 genre dimensions provide richer audio semantics at no cost
2. **Phase 2:** Hard negatives for exclusive tags (WalkingBass → negative for RollingBass)
3. **Phase 3:** +2048 PANN dims for complementary AudioSet-trained features

**Backward Compatibility:**
- Old 1280-dim models: TagClassifier will detect dimension mismatch and warn
- Models without tag groups: Continue working as binary classifiers
- ModelMetadata defaults preserve compatibility with existing models
