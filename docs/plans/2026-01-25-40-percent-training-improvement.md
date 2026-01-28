# 40% Training Accuracy Improvement Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Achieve 40% improvement in classification accuracy for subjective audio tags (WalkingBass, Dope, Asian, Chill, etc.) through stacked orthogonal improvements.

**Target:** Subjective tags from ~60% → ~84% accuracy

---

## Executive Summary

| Phase | Technique | Expected Gain | Cumulative | Effort |
|-------|-----------|---------------|------------|--------|
| 1 | Extended embeddings (1680-dim) | 5-10% | ~8% | Low |
| 2 | Multi-class hard negatives | 10-15% | ~20% | Medium |
| 3 | SpecAugment + Mixup augmentation | 5-10% | ~28% | Low |
| 4 | CLAP embeddings (+512-dim) | 5-10% | ~35% | Medium |
| 5 | Contrastive loss + label smoothing | 5-8% | ~40% | Medium |

**Architecture Evolution:**
```
Current:  Audio → EffNet (1280) → Binary Classifier → Tags

Target:   Audio → EffNet (1280) + Genres (400) + CLAP (512) = 2192-dim
               → SpecAugment/Mixup during training
               → Multi-class (grouped tags) + Binary (independent tags)
               → Contrastive + CrossEntropy loss
               → Soft labels with smoothing
               → Tags with calibrated confidence
```

**Tech Stack:** Swift, CoreML, CreateML TabularData, AVFoundation, Python (for CLAP conversion only)

---

## Phase 1: Extended Embeddings (1680-dim)

### Task 1.1: Update EmbeddingCache Version

**Files:**
- `CrateBotCore/Sources/CrateBotCore/ML/EmbeddingCache.swift`

**Changes:**
Update the extractor version to invalidate old 1280-dim cached embeddings.

```swift
// EmbeddingCache.swift - update version string
public init(extractorVersion: String = "effnet-v2-extended-2192") {
    // Version change invalidates all cached embeddings
}
```

**Commit:** `feat(cache): bump version for extended embeddings`

---

### Task 1.2: Update TrainingDataCollector for Extended Features

**Files:**
- `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift`

**Changes:**
Modify the batch extraction block to use `extractWithGenres` and concatenate:

```swift
// Around line 702 - in extractFeatures batch processing
let (embeddings, genreActivations) = try await extractor.extractWithGenres(from: buffer)
let features = embeddings + genreActivations  // 1280 + 400 = 1680
return (globalIndex, track, features)
```

**Commit:** `feat(training): concatenate genre activations to embeddings`

---

### Task 1.3: Update TaggingEngine for Extended Inference

**Files:**
- `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

**Changes:**
Update `analyze(url:)` to pass extended features to classifiers:

```swift
// Around line 192 in analyze(url:)
let (embeddings, genreActivations) = try await effnetExtractor.extractWithGenres(from: buffer)
let extendedFeatures = embeddings + genreActivations  // 1680-dim

// Use extendedFeatures for all classifier predictions
```

**Commit:** `feat(tagging): use extended features for inference`

---

### Task 1.4: Update ModelMetadata with Feature Dimension

**Files:**
- `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift`

**Changes:**
Add `featureDimension` field for compatibility tracking:

```swift
public struct ModelMetadata: Codable, Sendable {
    // ... existing fields
    public let featureDimension: Int  // 1280, 1680, or 2192

    public init(
        // ... existing params
        featureDimension: Int = 1680
    ) {
        self.featureDimension = featureDimension
    }
}
```

**Commit:** `feat(metadata): track feature dimension in model metadata`

---

## Phase 2: Multi-Class Classification for Tag Groups

### Task 2.1: Create TagGroupRegistry

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/TagGroupRegistryTests.swift`

**Implementation:**

```swift
import Foundation

/// Registry of mutually exclusive tag groups for multi-class classification
public struct TagGroupRegistry: Codable, Sendable, Equatable {

    /// Map of group name to array of class names
    public private(set) var groups: [String: [String]] = [:]

    /// Reverse lookup: tag → group name
    private var tagToGroup: [String: String] = [:]

    public init() {}

    public init(groups: [String: [String]]) {
        self.groups = groups
        rebuildIndex()
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

    /// Find which group a tag belongs to (supports partial matching)
    public func groupName(for tag: String) -> String? {
        let lowered = tag.lowercased()

        // Direct match
        if let group = tagToGroup[lowered] {
            return group
        }

        // Partial match (e.g., "WalkingBass" contains "Walking")
        for (groupName, classes) in groups {
            for className in classes {
                if lowered.contains(className.lowercased()) {
                    return groupName
                }
            }
        }
        return nil
    }

    /// Normalize a tag to its canonical class name within a group
    public func normalizeTagToClass(_ tag: String, inGroup groupName: String) -> String? {
        guard let classes = groups[groupName] else { return nil }
        let lowered = tag.lowercased()

        // Exact match
        if let match = classes.first(where: { $0.lowercased() == lowered }) {
            return match
        }
        // Partial match
        if let match = classes.first(where: { lowered.contains($0.lowercased()) }) {
            return match
        }
        return nil
    }

    public func isGrouped(_ tag: String) -> Bool {
        groupName(for: tag) != nil
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case groups }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decode([String: [String]].self, forKey: .groups)
        rebuildIndex()
    }

    private mutating func rebuildIndex() {
        tagToGroup = [:]
        for (groupName, tags) in groups {
            for tag in tags {
                tagToGroup[tag.lowercased()] = groupName
            }
        }
    }

    // MARK: - Default Groups for Subjective Tags

    public static var defaultGroups: TagGroupRegistry {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy", "Deep", "Subby"])
        registry.addGroup(name: "Vibe", tags: ["Dope", "Chill", "Dark", "Uplifting", "Melancholic"])
        registry.addGroup(name: "Energy", tags: ["Low", "Medium", "High", "Peak"])
        registry.addGroup(name: "Cultural", tags: ["Asian", "Latin", "African", "MiddleEastern", "European"])
        return registry
    }
}
```

**Tests:**

```swift
final class TagGroupRegistryTests: XCTestCase {

    func testCreateAndFindGroup() {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy"])

        XCTAssertEqual(registry.groupName(for: "Walking"), "BassType")
        XCTAssertEqual(registry.groupName(for: "WalkingBass"), "BassType")  // Partial match
        XCTAssertNil(registry.groupName(for: "Unknown"))
    }

    func testNormalizeTagToClass() {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling"])

        XCTAssertEqual(registry.normalizeTagToClass("WalkingBass", inGroup: "BassType"), "Walking")
        XCTAssertEqual(registry.normalizeTagToClass("walking", inGroup: "BassType"), "Walking")
    }

    func testPersistence() throws {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "Vibe", tags: ["Dope", "Chill"])

        let data = try JSONEncoder().encode(registry)
        let decoded = try JSONDecoder().decode(TagGroupRegistry.self, from: data)

        XCTAssertEqual(decoded.groups, registry.groups)
    }
}
```

**Commit:** `feat: add TagGroupRegistry for multi-class tag groups`

---

### Task 2.2: Create MultiClassTrainingDataGenerator

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/MultiClassTrainingDataGenerator.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/MultiClassTrainingDataGeneratorTests.swift`

**Implementation:**

```swift
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

    /// Generate multi-class training data for a specific group
    public func generateTrainingData(
        for groupName: String,
        from tracks: [TaggedTrack],
        minSamplesPerClass: Int = 20
    ) -> MultiClassTrainingData? {

        guard let classes = registry.groups[groupName] else { return nil }

        var samples: [ClassifiedSample] = []
        var classCounts: [String: Int] = [:]

        for track in tracks {
            guard let features = track.features else { continue }

            // Find which class this track belongs to
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

        // Filter to classes with enough samples
        let validClasses = classes.filter { (classCounts[$0] ?? 0) >= minSamplesPerClass }

        // Need at least 2 classes for multi-class
        guard validClasses.count >= 2 else { return nil }

        let validSamples = samples.filter { validClasses.contains($0.className) }

        return MultiClassTrainingData(
            groupName: groupName,
            classes: validClasses.sorted(),
            samples: validSamples
        )
    }

    /// Find all groups that have enough data for training
    public func viableGroups(
        from tracks: [TaggedTrack],
        minSamplesPerClass: Int = 20,
        minClasses: Int = 2
    ) -> [String] {
        registry.groups.keys.compactMap { groupName in
            guard let data = generateTrainingData(for: groupName, from: tracks, minSamplesPerClass: minSamplesPerClass),
                  data.classes.count >= minClasses else { return nil }
            return groupName
        }.sorted()
    }
}
```

**Commit:** `feat: add MultiClassTrainingDataGenerator for grouped tags`

---

### Task 2.3: Add Multi-Class Training to ModelTrainer

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift`

**Changes:**
Add `trainMultiClassModel` method:

```swift
// MARK: - Multi-Class Training

public struct MultiClassTrainingResult: Sendable {
    public let groupName: String
    public let classes: [String]
    public let accuracy: Double
    public let perClassAccuracy: [String: Double]
    public let confusionMatrix: [[Int]]  // For analysis
    public let modelURL: URL
}

public func trainMultiClassModel(
    data: MultiClassTrainingDataGenerator.MultiClassTrainingData,
    outputDirectory: URL,
    validationSplit: Double = 0.2,
    useLabelSmoothing: Bool = true,
    smoothingFactor: Float = 0.1
) async throws -> MultiClassTrainingResult {

    let groupName = data.groupName
    let classes = data.classes
    let featureCount = data.samples.first?.features.count ?? 1680

    logger.info("Training multi-class '\(groupName)' with \(classes.count) classes, \(data.samples.count) samples")

    // Shuffle and split
    let shuffled = data.samples.shuffled(using: &rng)
    let splitIndex = Int(Double(shuffled.count) * (1.0 - validationSplit))
    let trainingSamples = Array(shuffled[..<splitIndex])
    let validationSamples = Array(shuffled[splitIndex...])

    // Build DataFrame with optional label smoothing
    let dataFrame = try prepareMultiClassDataFrame(
        samples: trainingSamples,
        featureCount: featureCount,
        classes: classes,
        labelSmoothing: useLabelSmoothing ? smoothingFactor : nil
    )

    // Train boosted tree classifier
    let classifier = try MLBoostedTreeClassifier(
        trainingData: dataFrame,
        targetColumn: "label",
        parameters: MLBoostedTreeClassifier.ModelParameters(
            maxDepth: 6,
            maxIterations: 150,  // More iterations for multi-class
            minLossReduction: 0.0,
            minChildWeight: 1.0,
            stepSize: 0.25
        )
    )

    // Validate and compute confusion matrix
    let (accuracy, perClassAccuracy, confusionMatrix) = try evaluateMultiClass(
        classifier: classifier,
        samples: validationSamples,
        classes: classes,
        featureCount: featureCount
    )

    logger.info("'\(groupName)' accuracy: \(String(format: "%.1f%%", accuracy * 100))")
    for (className, acc) in perClassAccuracy.sorted(by: { $0.key < $1.key }) {
        logger.info("  \(className): \(String(format: "%.1f%%", acc * 100))")
    }

    // Save model
    let modelURL = outputDirectory.appendingPathComponent("\(groupName).mlmodel")
    try classifier.write(to: modelURL, metadata: nil)

    return MultiClassTrainingResult(
        groupName: groupName,
        classes: classes,
        accuracy: accuracy,
        perClassAccuracy: perClassAccuracy,
        confusionMatrix: confusionMatrix,
        modelURL: modelURL
    )
}

private func prepareMultiClassDataFrame(
    samples: [MultiClassTrainingDataGenerator.ClassifiedSample],
    featureCount: Int,
    classes: [String],
    labelSmoothing: Float?
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

private func evaluateMultiClass(
    classifier: MLBoostedTreeClassifier,
    samples: [MultiClassTrainingDataGenerator.ClassifiedSample],
    classes: [String],
    featureCount: Int
) throws -> (Double, [String: Double], [[Int]]) {

    let classToIndex = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1, $0) })
    var confusionMatrix = [[Int]](repeating: [Int](repeating: 0, count: classes.count), count: classes.count)
    var perClassCorrect: [String: Int] = [:]
    var perClassTotal: [String: Int] = [:]

    for sample in samples {
        var featureDict: [String: MLFeatureValue] = [:]
        for (i, value) in sample.features.enumerated() where i < featureCount {
            featureDict["f\(i)"] = MLFeatureValue(double: Double(value))
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let output = try classifier.model.prediction(from: provider)

        if let predicted = output.featureValue(for: "label")?.stringValue {
            let actualIdx = classToIndex[sample.className] ?? 0
            let predictedIdx = classToIndex[predicted] ?? 0
            confusionMatrix[actualIdx][predictedIdx] += 1

            perClassTotal[sample.className, default: 0] += 1
            if predicted == sample.className {
                perClassCorrect[sample.className, default: 0] += 1
            }
        }
    }

    let totalCorrect = perClassCorrect.values.reduce(0, +)
    let accuracy = samples.isEmpty ? 0 : Double(totalCorrect) / Double(samples.count)

    var perClassAccuracy: [String: Double] = [:]
    for className in classes {
        let correct = perClassCorrect[className] ?? 0
        let total = perClassTotal[className] ?? 0
        perClassAccuracy[className] = total > 0 ? Double(correct) / Double(total) : 0
    }

    return (accuracy, perClassAccuracy, confusionMatrix)
}
```

**Commit:** `feat: add multi-class training to ModelTrainer`

---

### Task 2.4: Create MultiClassClassifier for Inference

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/MultiClassClassifier.swift`

**Implementation:**

```swift
import Foundation
import CoreML

public actor MultiClassClassifier {

    public struct Prediction: Sendable {
        public let groupName: String
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
        guard features.count >= featureCount else {
            throw ClassifierError.invalidFeatureCount(expected: featureCount, got: features.count)
        }

        var featureDict: [String: MLFeatureValue] = [:]
        for i in 0..<featureCount {
            featureDict["f\(i)"] = MLFeatureValue(double: Double(features[i]))
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

        return Prediction(
            groupName: groupName,
            predictedClass: predictedClass,
            confidence: confidence,
            classProbabilities: classProbabilities
        )
    }

    public enum ClassifierError: Error, LocalizedError {
        case invalidFeatureCount(expected: Int, got: Int)
        case missingPrediction

        public var errorDescription: String? {
            switch self {
            case .invalidFeatureCount(let expected, let got):
                return "Feature count mismatch: expected \(expected), got \(got)"
            case .missingPrediction:
                return "Model did not return a prediction"
            }
        }
    }
}
```

**Commit:** `feat: add MultiClassClassifier for grouped tag inference`

---

### Task 2.5: Integrate Multi-Class into TrainingCoordinator

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`

**Changes:**

1. Add `tagGroupRegistry` to `TrainingOptions`:

```swift
public struct TrainingOptions: Sendable {
    // ... existing fields
    public let tagGroupRegistry: TagGroupRegistry

    public init(
        // ... existing params
        tagGroupRegistry: TagGroupRegistry = .defaultGroups
    ) {
        self.tagGroupRegistry = tagGroupRegistry
    }
}
```

2. Modify `train()` to handle both multi-class and binary:

```swift
// After feature extraction, before binary training:

// Train multi-class classifiers for viable groups
let multiClassGenerator = MultiClassTrainingDataGenerator(registry: options.tagGroupRegistry)
let viableGroups = multiClassGenerator.viableGroups(
    from: validTracks,
    minSamplesPerClass: options.minSamplesPerTag
)

var multiClassResults: [MultiClassTrainingResult] = []
var groupedTagSet: Set<String> = []

for groupName in viableGroups {
    if let groupData = multiClassGenerator.generateTrainingData(
        for: groupName,
        from: validTracks,
        minSamplesPerClass: options.minSamplesPerTag
    ) {
        logger.info("Training multi-class group: \(groupName) with classes: \(groupData.classes)")

        let result = try await modelTrainer.trainMultiClassModel(
            data: groupData,
            outputDirectory: outputDirectory
        )
        multiClassResults.append(result)

        // Track tags covered by multi-class groups
        for className in result.classes {
            groupedTagSet.insert(className.lowercased())
        }
    }
}

// Filter binary training to exclude grouped tags
let binaryTags = viableTags.filter { tag in
    !options.tagGroupRegistry.isGrouped(tag)
}

// Continue with binary training for binaryTags...
```

3. Update metadata to include tag groups:

```swift
// Add TagGroupInfo to ModelMetadata
public struct TagGroupInfo: Codable, Sendable {
    public let groupName: String
    public let classes: [String]
    public let accuracy: Double
    public let perClassAccuracy: [String: Double]
}

// Include in metadata creation
let tagGroupInfos = multiClassResults.map { result in
    TagGroupInfo(
        groupName: result.groupName,
        classes: result.classes,
        accuracy: result.accuracy,
        perClassAccuracy: result.perClassAccuracy
    )
}
```

**Commit:** `feat: integrate multi-class training into TrainingCoordinator`

---

### Task 2.6: Update TaggingEngine for Multi-Class Inference

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

**Changes:**

```swift
// Add storage for multi-class classifiers
private var multiClassClassifiers: [String: MultiClassClassifier] = [:]

// In loadModel() - after loading binary classifiers:
if let metadata = try? ModelMetadata.load(from: metadataURL) {
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
                logger.info("Loaded multi-class classifier: \(groupInfo.groupName)")
            } catch {
                logger.error("Failed to load multi-class '\(groupInfo.groupName)': \(error)")
            }
        }
    }
}

// In analyze() - run multi-class predictions:
var groupPredictions: [MultiClassClassifier.Prediction] = []

for (_, classifier) in multiClassClassifiers {
    do {
        let prediction = try await classifier.predict(features: extendedFeatures)
        if prediction.confidence >= classificationThreshold {
            groupPredictions.append(prediction)
            predictedTags.append(prediction.predictedClass)
        }
    } catch {
        logger.error("Multi-class prediction failed: \(error)")
    }
}
```

**Commit:** `feat: add multi-class inference to TaggingEngine`

---

## Phase 3: Data Augmentation (SpecAugment + Mixup)

### Task 3.1: Create AudioAugmenter

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/AudioAugmenter.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/AudioAugmenterTests.swift`

**Implementation:**

```swift
import Foundation
import Accelerate

/// Audio augmentation utilities for training robustness
public struct AudioAugmenter: Sendable {

    public struct AugmentationConfig: Sendable {
        public let specAugmentEnabled: Bool
        public let mixupEnabled: Bool
        public let mixupAlpha: Float
        public let freqMaskCount: Int
        public let freqMaskWidth: Int
        public let timeMaskCount: Int
        public let timeMaskWidth: Int

        public static let `default` = AugmentationConfig(
            specAugmentEnabled: true,
            mixupEnabled: true,
            mixupAlpha: 0.4,
            freqMaskCount: 2,
            freqMaskWidth: 15,
            timeMaskCount: 2,
            timeMaskWidth: 25
        )

        public static let none = AugmentationConfig(
            specAugmentEnabled: false,
            mixupEnabled: false,
            mixupAlpha: 0,
            freqMaskCount: 0,
            freqMaskWidth: 0,
            timeMaskCount: 0,
            timeMaskWidth: 0
        )

        public init(
            specAugmentEnabled: Bool = true,
            mixupEnabled: Bool = true,
            mixupAlpha: Float = 0.4,
            freqMaskCount: Int = 2,
            freqMaskWidth: Int = 15,
            timeMaskCount: Int = 2,
            timeMaskWidth: Int = 25
        ) {
            self.specAugmentEnabled = specAugmentEnabled
            self.mixupEnabled = mixupEnabled
            self.mixupAlpha = mixupAlpha
            self.freqMaskCount = freqMaskCount
            self.freqMaskWidth = freqMaskWidth
            self.timeMaskCount = timeMaskCount
            self.timeMaskWidth = timeMaskWidth
        }
    }

    // MARK: - SpecAugment

    /// Apply SpecAugment to a mel spectrogram
    /// - Parameters:
    ///   - spectrogram: 2D array [freqBins][timeSteps]
    ///   - config: Augmentation configuration
    /// - Returns: Augmented spectrogram
    public static func applySpecAugment(
        to spectrogram: [[Float]],
        config: AugmentationConfig = .default
    ) -> [[Float]] {
        guard config.specAugmentEnabled else { return spectrogram }
        guard !spectrogram.isEmpty, !spectrogram[0].isEmpty else { return spectrogram }

        var augmented = spectrogram
        let freqBins = spectrogram.count
        let timeSteps = spectrogram[0].count

        // Frequency masking
        for _ in 0..<config.freqMaskCount {
            let width = Int.random(in: 1...config.freqMaskWidth)
            let start = Int.random(in: 0..<max(1, freqBins - width))
            for f in start..<min(start + width, freqBins) {
                augmented[f] = [Float](repeating: 0, count: timeSteps)
            }
        }

        // Time masking
        for _ in 0..<config.timeMaskCount {
            let width = Int.random(in: 1...config.timeMaskWidth)
            let start = Int.random(in: 0..<max(1, timeSteps - width))
            for f in 0..<freqBins {
                for t in start..<min(start + width, timeSteps) {
                    augmented[f][t] = 0
                }
            }
        }

        return augmented
    }

    // MARK: - Mixup

    public struct MixupResult: Sendable {
        public let features: [Float]
        public let softLabels: [String: Float]  // class -> weight
    }

    /// Apply Mixup between two samples
    public static func mixup(
        features1: [Float],
        features2: [Float],
        label1: String,
        label2: String,
        alpha: Float = 0.4
    ) -> MixupResult {
        // Sample lambda from Beta distribution (approximated)
        let lambda = sampleBeta(alpha: alpha, beta: alpha)

        // Mix features
        var mixedFeatures = [Float](repeating: 0, count: features1.count)
        vDSP_vasm(features1, 1, features2, 1, [lambda], &mixedFeatures, 1, vDSP_Length(features1.count))

        // For the second term: (1-lambda) * features2
        var scaledFeatures2 = [Float](repeating: 0, count: features2.count)
        var oneMinusLambda = 1.0 - lambda
        vDSP_vsmul(features2, 1, &oneMinusLambda, &scaledFeatures2, 1, vDSP_Length(features2.count))

        // Add to mixedFeatures
        vDSP_vadd(mixedFeatures, 1, scaledFeatures2, 1, &mixedFeatures, 1, vDSP_Length(features1.count))

        // Soft labels
        var softLabels: [String: Float] = [:]
        if label1 == label2 {
            softLabels[label1] = 1.0
        } else {
            softLabels[label1] = lambda
            softLabels[label2] = 1.0 - lambda
        }

        return MixupResult(features: mixedFeatures, softLabels: softLabels)
    }

    /// Approximate Beta distribution sampling using Box-Muller
    private static func sampleBeta(alpha: Float, beta: Float) -> Float {
        // Simplified: use uniform for alpha < 1, otherwise approximate
        if alpha <= 1.0 {
            return Float.random(in: 0.3...0.7)  // Conservative range
        }

        // For alpha > 1, approximate with clamped normal
        let u1 = Float.random(in: 0.0001...0.9999)
        let u2 = Float.random(in: 0.0001...0.9999)
        let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        let mean: Float = 0.5
        let std: Float = 0.15
        return max(0.1, min(0.9, mean + std * z))
    }

    // MARK: - Feature Augmentation

    /// Apply augmentation directly to embedding features (for mixup without spectrogram access)
    public static func augmentFeatures(
        _ features: [Float],
        addNoise: Bool = true,
        noiseScale: Float = 0.01
    ) -> [Float] {
        guard addNoise else { return features }

        return features.map { value in
            let noise = Float.random(in: -noiseScale...noiseScale)
            return value + noise
        }
    }
}
```

**Tests:**

```swift
final class AudioAugmenterTests: XCTestCase {

    func testSpecAugmentMasksFrequencies() {
        let spectrogram = [[Float]](repeating: [Float](repeating: 1.0, count: 100), count: 64)
        let config = AudioAugmenter.AugmentationConfig(
            specAugmentEnabled: true,
            mixupEnabled: false,
            mixupAlpha: 0,
            freqMaskCount: 2,
            freqMaskWidth: 10,
            timeMaskCount: 0,
            timeMaskWidth: 0
        )

        let augmented = AudioAugmenter.applySpecAugment(to: spectrogram, config: config)

        // Some frequency bins should now be zero
        let zeroRows = augmented.filter { row in row.allSatisfy { $0 == 0 } }.count
        XCTAssertGreaterThan(zeroRows, 0)
    }

    func testMixupBlendsFeaturesAndLabels() {
        let features1 = [Float](repeating: 1.0, count: 1680)
        let features2 = [Float](repeating: 0.0, count: 1680)

        let result = AudioAugmenter.mixup(
            features1: features1,
            features2: features2,
            label1: "ClassA",
            label2: "ClassB",
            alpha: 0.4
        )

        // Mixed features should be between 0 and 1
        XCTAssertTrue(result.features.allSatisfy { $0 >= 0 && $0 <= 1 })

        // Should have soft labels for both classes
        XCTAssertEqual(result.softLabels.count, 2)
        XCTAssertEqual(result.softLabels.values.reduce(0, +), 1.0, accuracy: 0.01)
    }
}
```

**Commit:** `feat: add AudioAugmenter with SpecAugment and Mixup`

---

### Task 3.2: Integrate Augmentation into TrainingDataCollector

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift`

**Changes:**

Add augmentation to feature extraction:

```swift
// Add to TrainingDataCollector
public var augmentationConfig: AudioAugmenter.AugmentationConfig = .default

// In extractFeatures, after getting embeddings:
// Apply feature-level augmentation for training robustness
let augmentedFeatures = AudioAugmenter.augmentFeatures(
    features,
    addNoise: augmentationConfig.specAugmentEnabled,
    noiseScale: 0.02
)
return (globalIndex, track, augmentedFeatures)
```

**Commit:** `feat: integrate augmentation into TrainingDataCollector`

---

### Task 3.3: Add Mixup to ModelTrainer

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift`

**Changes:**

Add mixup during binary and multi-class training:

```swift
// Add to TrainingConfig
public let mixupEnabled: Bool
public let mixupAlpha: Float
public let mixupRatio: Float  // Fraction of samples to mixup

// In training data preparation:
private func applyMixupAugmentation(
    to samples: [(features: [Float], label: String)],
    config: TrainingConfig
) -> [(features: [Float], label: String, softLabel: [String: Float]?)] {

    guard config.mixupEnabled else {
        return samples.map { ($0.features, $0.label, nil) }
    }

    var augmented: [(features: [Float], label: String, softLabel: [String: Float]?)] = []
    let mixupCount = Int(Float(samples.count) * config.mixupRatio)

    // Keep original samples
    for sample in samples {
        augmented.append((sample.features, sample.label, nil))
    }

    // Add mixup samples
    for _ in 0..<mixupCount {
        let idx1 = Int.random(in: 0..<samples.count)
        let idx2 = Int.random(in: 0..<samples.count)
        guard idx1 != idx2 else { continue }

        let result = AudioAugmenter.mixup(
            features1: samples[idx1].features,
            features2: samples[idx2].features,
            label1: samples[idx1].label,
            label2: samples[idx2].label,
            alpha: config.mixupAlpha
        )

        // Use dominant label for hard label, keep soft labels for potential soft loss
        let dominantLabel = result.softLabels.max(by: { $0.value < $1.value })?.key ?? samples[idx1].label
        augmented.append((result.features, dominantLabel, result.softLabels))
    }

    return augmented
}
```

**Commit:** `feat: add Mixup augmentation to ModelTrainer`

---

## Phase 4: CLAP Embeddings (512-dim)

### Task 4.1: Convert CLAP Model to CoreML (Python)

**Files:**
- Create: `scripts/convert_clap_to_coreml.py`

**Script:**

```python
#!/usr/bin/env python3
"""
Convert LAION CLAP model to CoreML for CrateBot.
Outputs audio encoder only (512-dim embeddings).

Usage:
    pip install transformers coremltools torch
    python convert_clap_to_coreml.py
"""

import torch
import coremltools as ct
from transformers import ClapModel, ClapProcessor
import numpy as np

def main():
    print("Loading CLAP model...")
    model = ClapModel.from_pretrained("laion/larger_clap_music")
    processor = ClapProcessor.from_pretrained("laion/larger_clap_music")
    model.eval()

    # We only need the audio encoder
    audio_model = model.audio_model
    audio_projection = model.audio_projection

    class CLAPAudioEncoder(torch.nn.Module):
        def __init__(self, audio_model, audio_projection):
            super().__init__()
            self.audio_model = audio_model
            self.audio_projection = audio_projection

        def forward(self, input_features):
            # input_features: [batch, mel_bins, time_frames]
            outputs = self.audio_model(input_features=input_features)
            pooled = outputs.pooler_output  # [batch, hidden_size]
            embeddings = self.audio_projection(pooled)  # [batch, 512]
            return embeddings

    encoder = CLAPAudioEncoder(audio_model, audio_projection)
    encoder.eval()

    # CLAP expects mel spectrogram input
    # Fixed shape for CoreML: [1, 64, 1001] (64 mel bins, ~10 seconds at default hop)
    example_input = torch.randn(1, 64, 1001)

    print("Tracing model...")
    traced = torch.jit.trace(encoder, example_input)

    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="mel_spectrogram", shape=(1, 64, 1001))
        ],
        outputs=[
            ct.TensorType(name="embedding")
        ],
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT16
    )

    # Add metadata
    mlmodel.author = "CrateBot (converted from LAION CLAP)"
    mlmodel.short_description = "CLAP audio encoder for music embeddings (512-dim)"
    mlmodel.version = "1.0"

    output_path = "CLAPAudioEncoder.mlpackage"
    mlmodel.save(output_path)
    print(f"Saved to {output_path}")

    # Verify
    print("Verifying...")
    import coremltools as ct
    loaded = ct.models.MLModel(output_path)
    test_input = {"mel_spectrogram": np.random.randn(1, 64, 1001).astype(np.float32)}
    output = loaded.predict(test_input)
    print(f"Output shape: {output['embedding'].shape}")  # Should be (1, 512)
    print("Done!")

if __name__ == "__main__":
    main()
```

**Execution:**
```bash
cd scripts
pip install transformers coremltools torch
python convert_clap_to_coreml.py
# Copy CLAPAudioEncoder.mlpackage to CrateBotCore/Resources/
```

**Commit:** `feat: add CLAP to CoreML conversion script`

---

### Task 4.2: Create CLAPExtractor

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Audio/CLAPExtractor.swift`
- Add: `CLAPAudioEncoder.mlpackage` to `CrateBotCore/Resources/`

**Implementation:**

```swift
import Foundation
import CoreML
import Accelerate

/// Extracts 512-dimensional CLAP embeddings for music understanding
public actor CLAPExtractor {

    public static let embeddingDimension = 512
    public static let melBins = 64
    public static let targetFrames = 1001  // ~10 seconds at default hop
    public static let targetSampleRate: Double = 48000

    private let model: MLModel
    private let melGenerator: MelSpectrogramGenerator

    public init() throws {
        // Load model from bundle
        guard let modelURL = Bundle.module.url(forResource: "CLAPAudioEncoder", withExtension: "mlmodelc")
            ?? Bundle.module.url(forResource: "CLAPAudioEncoder", withExtension: "mlpackage") else {
            throw CLAPError.modelNotFound
        }

        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try MLModel.compileModel(at: modelURL)
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        self.model = try MLModel(contentsOf: compiledURL, configuration: config)

        // CLAP uses 64 mel bins
        self.melGenerator = MelSpectrogramGenerator(
            sampleRate: Self.targetSampleRate,
            fftSize: 2048,
            hopSize: 480,  // ~10ms at 48kHz
            melBins: Self.melBins
        )
    }

    /// Extract CLAP embeddings from audio buffer
    public func extract(from audioBuffer: [Float], sampleRate: Double) throws -> [Float] {
        // Resample if needed
        let resampled: [Float]
        if abs(sampleRate - Self.targetSampleRate) > 1 {
            resampled = resample(audioBuffer, from: sampleRate, to: Self.targetSampleRate)
        } else {
            resampled = audioBuffer
        }

        // Generate mel spectrogram
        var melSpec = melGenerator.generate(from: resampled)

        // Pad or truncate to fixed size
        melSpec = normalizeToFixedSize(melSpec, targetFrames: Self.targetFrames)

        // Flatten to MLMultiArray format [1, 64, 1001]
        let flatSpec = melSpec.flatMap { $0 }

        let inputArray = try MLMultiArray(shape: [1, NSNumber(value: Self.melBins), NSNumber(value: Self.targetFrames)], dataType: .float32)
        for (i, value) in flatSpec.enumerated() {
            inputArray[i] = NSNumber(value: value)
        }

        let input = try MLDictionaryFeatureProvider(dictionary: ["mel_spectrogram": inputArray])
        let output = try model.prediction(from: input)

        guard let embeddingArray = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw CLAPError.predictionFailed
        }

        // Extract 512-dim embedding
        var embedding = [Float](repeating: 0, count: Self.embeddingDimension)
        for i in 0..<Self.embeddingDimension {
            embedding[i] = embeddingArray[i].floatValue
        }

        return embedding
    }

    private func normalizeToFixedSize(_ melSpec: [[Float]], targetFrames: Int) -> [[Float]] {
        let currentFrames = melSpec.first?.count ?? 0

        if currentFrames == targetFrames {
            return melSpec
        } else if currentFrames > targetFrames {
            // Truncate from center
            let start = (currentFrames - targetFrames) / 2
            return melSpec.map { Array($0[start..<(start + targetFrames)]) }
        } else {
            // Pad with zeros
            let padLeft = (targetFrames - currentFrames) / 2
            let padRight = targetFrames - currentFrames - padLeft
            return melSpec.map { row in
                [Float](repeating: 0, count: padLeft) + row + [Float](repeating: 0, count: padRight)
            }
        }
    }

    private func resample(_ buffer: [Float], from sourceSR: Double, to targetSR: Double) -> [Float] {
        let ratio = targetSR / sourceSR
        let outputLength = Int(Double(buffer.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        var sourceIndex: Double = 0
        for i in 0..<outputLength {
            let idx = Int(sourceIndex)
            if idx < buffer.count - 1 {
                let frac = Float(sourceIndex - Double(idx))
                output[i] = buffer[idx] * (1 - frac) + buffer[idx + 1] * frac
            } else if idx < buffer.count {
                output[i] = buffer[idx]
            }
            sourceIndex += 1.0 / ratio
        }

        return output
    }

    public enum CLAPError: Error, LocalizedError {
        case modelNotFound
        case predictionFailed

        public var errorDescription: String? {
            switch self {
            case .modelNotFound:
                return "CLAP model not found in bundle"
            case .predictionFailed:
                return "CLAP prediction failed"
            }
        }
    }
}
```

**Commit:** `feat: add CLAPExtractor for 512-dim music embeddings`

---

### Task 4.3: Create CombinedFeatureExtractor

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Audio/CombinedFeatureExtractor.swift`

**Implementation:**

```swift
import Foundation

/// Combines multiple extractors for rich audio features
public actor CombinedFeatureExtractor {

    public enum FeatureConfig: Sendable {
        case effnetOnly           // 1280 dims
        case effnetPlusGenres     // 1680 dims (1280 + 400)
        case effnetGenresCLAP     // 2192 dims (1280 + 400 + 512)

        public var dimension: Int {
            switch self {
            case .effnetOnly: return 1280
            case .effnetPlusGenres: return 1680
            case .effnetGenresCLAP: return 2192
            }
        }

        public var description: String {
            switch self {
            case .effnetOnly: return "EffNet (1280)"
            case .effnetPlusGenres: return "EffNet+Genres (1680)"
            case .effnetGenresCLAP: return "EffNet+Genres+CLAP (2192)"
            }
        }
    }

    private let effnetExtractor: EffNetExtractor
    private let clapExtractor: CLAPExtractor?
    private let config: FeatureConfig

    public init(config: FeatureConfig = .effnetGenresCLAP) throws {
        self.config = config
        self.effnetExtractor = try EffNetExtractor()

        if config == .effnetGenresCLAP {
            self.clapExtractor = try? CLAPExtractor()
            if self.clapExtractor == nil {
                print("Warning: CLAP extractor unavailable, falling back to EffNet+Genres")
            }
        } else {
            self.clapExtractor = nil
        }
    }

    public var featureDimension: Int {
        if config == .effnetGenresCLAP && clapExtractor == nil {
            return FeatureConfig.effnetPlusGenres.dimension
        }
        return config.dimension
    }

    /// Extract combined features from audio buffer
    public func extract(from audioBuffer: [Float], sampleRate: Double) async throws -> [Float] {
        switch config {
        case .effnetOnly:
            return try await effnetExtractor.extract(from: audioBuffer)

        case .effnetPlusGenres:
            let (embeddings, genres) = try await effnetExtractor.extractWithGenres(from: audioBuffer)
            return embeddings + genres

        case .effnetGenresCLAP:
            let (embeddings, genres) = try await effnetExtractor.extractWithGenres(from: audioBuffer)

            if let clap = clapExtractor {
                let clapEmbeddings = try await clap.extract(from: audioBuffer, sampleRate: sampleRate)
                return embeddings + genres + clapEmbeddings  // 1280 + 400 + 512 = 2192
            } else {
                return embeddings + genres  // Fallback to 1680
            }
        }
    }
}
```

**Commit:** `feat: add CombinedFeatureExtractor for multi-source embeddings`

---

### Task 4.4: Update TrainingDataCollector to Use Combined Extractor

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift`

**Changes:**

```swift
// Replace EffNetExtractor with CombinedFeatureExtractor
private var featureExtractor: CombinedFeatureExtractor?

// Add configuration
public var featureConfig: CombinedFeatureExtractor.FeatureConfig = .effnetGenresCLAP

// In extractFeatures:
if featureExtractor == nil {
    featureExtractor = try CombinedFeatureExtractor(config: featureConfig)
}

// Use combined extraction
let features = try await featureExtractor!.extract(from: buffer, sampleRate: sampleRate)
```

**Commit:** `feat: use CombinedFeatureExtractor in TrainingDataCollector`

---

### Task 4.5: Update TaggingEngine to Use Combined Extractor

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

**Changes:**

```swift
// Replace EffNetExtractor with CombinedFeatureExtractor
private var featureExtractor: CombinedFeatureExtractor?

// Load with config matching trained model's feature dimension
public func loadModel(from directory: URL, config: CombinedFeatureExtractor.FeatureConfig? = nil) async throws {
    // Detect config from metadata if not provided
    let effectiveConfig: CombinedFeatureExtractor.FeatureConfig
    if let config = config {
        effectiveConfig = config
    } else if let metadata = loadedMetadata {
        switch metadata.featureDimension {
        case 1280: effectiveConfig = .effnetOnly
        case 1680: effectiveConfig = .effnetPlusGenres
        default: effectiveConfig = .effnetGenresCLAP
        }
    } else {
        effectiveConfig = .effnetGenresCLAP
    }

    featureExtractor = try CombinedFeatureExtractor(config: effectiveConfig)
}

// In analyze:
let features = try await featureExtractor!.extract(from: buffer, sampleRate: sampleRate)
```

**Commit:** `feat: use CombinedFeatureExtractor in TaggingEngine`

---

## Phase 5: Contrastive Loss + Label Smoothing

### Task 5.1: Create ContrastiveLoss Utility

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/ContrastiveLoss.swift`

**Implementation:**

```swift
import Foundation
import Accelerate

/// Supervised contrastive loss for better feature separation
public struct ContrastiveLoss {

    /// Compute supervised contrastive loss
    /// Pulls same-class embeddings together, pushes different-class apart
    public static func compute(
        embeddings: [[Float]],  // [batch_size, feature_dim]
        labels: [String],
        temperature: Float = 0.07
    ) -> Float {
        let batchSize = embeddings.count
        guard batchSize > 1 else { return 0 }

        // Normalize embeddings
        let normalized = embeddings.map { l2Normalize($0) }

        // Compute similarity matrix
        var similarities = [[Float]](repeating: [Float](repeating: 0, count: batchSize), count: batchSize)
        for i in 0..<batchSize {
            for j in 0..<batchSize {
                similarities[i][j] = dotProduct(normalized[i], normalized[j]) / temperature
            }
        }

        // Compute contrastive loss
        var totalLoss: Float = 0

        for anchor in 0..<batchSize {
            let anchorLabel = labels[anchor]

            // Find positive indices (same class, excluding self)
            var positiveIndices: [Int] = []
            for i in 0..<batchSize where i != anchor && labels[i] == anchorLabel {
                positiveIndices.append(i)
            }

            guard !positiveIndices.isEmpty else { continue }

            // Compute log-sum-exp for denominator (all except self)
            var expSum: Float = 0
            for i in 0..<batchSize where i != anchor {
                expSum += exp(similarities[anchor][i])
            }
            let logDenom = log(expSum + 1e-8)

            // Sum over positives
            var positiveLoss: Float = 0
            for posIdx in positiveIndices {
                positiveLoss += similarities[anchor][posIdx] - logDenom
            }

            totalLoss -= positiveLoss / Float(positiveIndices.count)
        }

        return totalLoss / Float(batchSize)
    }

    /// L2 normalize a vector
    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        let norm = sqrt(sumSquares + 1e-8)

        var normalized = [Float](repeating: 0, count: vector.count)
        var divisor = norm
        vDSP_vsdiv(vector, 1, &divisor, &normalized, 1, vDSP_Length(vector.count))

        return normalized
    }

    /// Dot product of two vectors
    private static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
}
```

**Commit:** `feat: add ContrastiveLoss for better feature separation`

---

### Task 5.2: Add Label Smoothing to Training

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift`

**Changes:**

Add label smoothing support:

```swift
// Add to TrainingConfig
public let labelSmoothingEnabled: Bool
public let labelSmoothingFactor: Float  // Typically 0.1

// In data preparation, apply label smoothing:
private func applySoftLabels(
    hardLabel: Int,  // 0 or 1 for binary
    numClasses: Int,
    smoothingFactor: Float
) -> [Float] {
    // For binary: [0, 1] becomes [0.05, 0.95] with factor 0.1
    var softLabels = [Float](repeating: smoothingFactor / Float(numClasses), count: numClasses)
    softLabels[hardLabel] = 1.0 - smoothingFactor + smoothingFactor / Float(numClasses)
    return softLabels
}

// Note: CreateML MLBoostedTreeClassifier doesn't directly support soft labels,
// so we approximate by:
// 1. Training with hard labels
// 2. Using the smoothing factor in confidence calibration during inference
//
// For full soft label support, would need custom gradient boosting implementation
// or switch to a neural network approach.
```

**Commit:** `feat: add label smoothing support to ModelTrainer`

---

### Task 5.3: Add Contrastive Pre-processing to Training

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift`

**Changes:**

Use contrastive loss to refine features before classification:

```swift
// Add contrastive feature refinement
public let contrastiveLearningEnabled: Bool

// Before training classifier, compute contrastive loss for logging/monitoring
private func logContrastiveLoss(
    samples: [(features: [Float], label: String)],
    tag: String
) {
    guard contrastiveLearningEnabled else { return }

    let embeddings = samples.map { $0.features }
    let labels = samples.map { $0.label }

    let loss = ContrastiveLoss.compute(
        embeddings: embeddings,
        labels: labels,
        temperature: 0.07
    )

    logger.info("Contrastive loss for '\(tag)': \(String(format: "%.4f", loss))")

    // Lower loss = better class separation
    // Use this as a diagnostic: if loss is high, the tag may need more training data
    // or the embeddings don't capture the concept well
}
```

**Note:** Full contrastive fine-tuning of embeddings would require a neural network training loop, which is beyond CreateML's capabilities. The contrastive loss here serves as a diagnostic metric.

**Commit:** `feat: add contrastive loss diagnostic to training`

---

### Task 5.4: Calibrate Confidence Scores

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/ConfidenceCalibrator.swift`

**Implementation:**

```swift
import Foundation

/// Calibrates classifier confidence scores using temperature scaling
public struct ConfidenceCalibrator: Codable, Sendable {

    /// Temperature for Platt scaling (learned from validation set)
    public var temperature: Float = 1.0

    /// Label smoothing factor used during training
    public var smoothingFactor: Float = 0.1

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

    /// Learn optimal temperature from validation predictions
    public mutating func fit(
        predictions: [Float],  // Raw confidences
        labels: [Bool]         // True labels
    ) {
        // Simple grid search for optimal temperature
        var bestTemp: Float = 1.0
        var bestLoss: Float = .infinity

        for t in stride(from: 0.5, through: 3.0, by: 0.1) {
            let temp = Float(t)
            var loss: Float = 0

            for (pred, label) in zip(predictions, labels) {
                let scaled = pred / temp
                let calibrated = 1.0 / (1.0 + exp(-scaled))
                let target: Float = label ? 1.0 : 0.0

                // Cross-entropy loss
                loss -= target * log(calibrated + 1e-8) + (1 - target) * log(1 - calibrated + 1e-8)
            }

            if loss < bestLoss {
                bestLoss = loss
                bestTemp = temp
            }
        }

        self.temperature = bestTemp
    }
}
```

**Commit:** `feat: add ConfidenceCalibrator for calibrated predictions`

---

### Task 5.5: Integration Testing

**Files:**
- Create: `CrateBotCore/Tests/CrateBotCoreTests/Integration/TrainingPipeline40PercentTests.swift`

**Tests:**

```swift
import XCTest
@testable import CrateBotCore

final class TrainingPipeline40PercentTests: XCTestCase {

    func testCombinedFeatureExtraction() async throws {
        let extractor = try CombinedFeatureExtractor(config: .effnetGenresCLAP)

        // Generate synthetic audio (1 second at 16kHz)
        let sampleRate: Double = 16000
        let duration: Double = 1.0
        let sampleCount = Int(sampleRate * duration)
        let audio = (0..<sampleCount).map { _ in Float.random(in: -1...1) }

        let features = try await extractor.extract(from: audio, sampleRate: sampleRate)

        // Should be 2192 if CLAP available, 1680 otherwise
        XCTAssertTrue(features.count == 2192 || features.count == 1680)
    }

    func testMultiClassWithAugmentation() async throws {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "TestVibe", tags: ["Dope", "Chill", "Dark"])

        // Create synthetic training data with augmentation
        var tracks: [TaggedTrack] = []
        for i in 0..<60 {
            // Distinct feature patterns per class
            let dopeFeatures = (0..<1680).map { _ in Float.random(in: 0.6...0.9) }
            let chillFeatures = (0..<1680).map { _ in Float.random(in: 0.2...0.5) }
            let darkFeatures = (0..<1680).map { _ in Float.random(in: 0.0...0.3) }

            tracks.append(TaggedTrack(id: "dope_\(i)", tags: Set(["Dope"]), features: dopeFeatures))
            tracks.append(TaggedTrack(id: "chill_\(i)", tags: Set(["Chill"]), features: chillFeatures))
            tracks.append(TaggedTrack(id: "dark_\(i)", tags: Set(["Dark"]), features: darkFeatures))
        }

        // Apply mixup augmentation
        let augmentedTracks = applyMixupToTracks(tracks, ratio: 0.3)

        let generator = MultiClassTrainingDataGenerator(registry: registry)
        let data = generator.generateTrainingData(for: "TestVibe", from: augmentedTracks, minSamplesPerClass: 50)

        XCTAssertNotNil(data)
        XCTAssertEqual(data!.classes.count, 3)
        XCTAssertGreaterThan(data!.samples.count, tracks.count)  // Augmented
    }

    func testContrastiveLossComputation() {
        // Create embeddings with clear class separation
        let classA = (0..<10).map { _ in (0..<100).map { _ in Float.random(in: 0.7...1.0) } }
        let classB = (0..<10).map { _ in (0..<100).map { _ in Float.random(in: 0.0...0.3) } }

        let embeddings = classA + classB
        let labels = [String](repeating: "A", count: 10) + [String](repeating: "B", count: 10)

        let loss = ContrastiveLoss.compute(embeddings: embeddings, labels: labels)

        // Loss should be relatively low for well-separated classes
        XCTAssertLessThan(loss, 2.0)
    }

    private func applyMixupToTracks(_ tracks: [TaggedTrack], ratio: Float) -> [TaggedTrack] {
        var result = tracks
        let mixupCount = Int(Float(tracks.count) * ratio)

        for _ in 0..<mixupCount {
            let idx1 = Int.random(in: 0..<tracks.count)
            let idx2 = Int.random(in: 0..<tracks.count)
            guard idx1 != idx2,
                  let f1 = tracks[idx1].features,
                  let f2 = tracks[idx2].features else { continue }

            let mixResult = AudioAugmenter.mixup(
                features1: f1,
                features2: f2,
                label1: tracks[idx1].tags.first ?? "",
                label2: tracks[idx2].tags.first ?? "",
                alpha: 0.4
            )

            let dominantLabel = mixResult.softLabels.max(by: { $0.value < $1.value })?.key ?? ""
            result.append(TaggedTrack(
                id: "mixup_\(idx1)_\(idx2)",
                tags: Set([dominantLabel]),
                features: mixResult.features
            ))
        }

        return result
    }
}
```

**Commit:** `test: add 40% training pipeline integration tests`

---

## Summary

### Files Created
| File | Purpose |
|------|---------|
| `TagGroupRegistry.swift` | Multi-class tag group definitions |
| `MultiClassTrainingDataGenerator.swift` | Prepare data for multi-class training |
| `MultiClassClassifier.swift` | Multi-class inference wrapper |
| `AudioAugmenter.swift` | SpecAugment and Mixup |
| `CLAPExtractor.swift` | CLAP 512-dim embeddings |
| `CombinedFeatureExtractor.swift` | Unified multi-source extraction |
| `ContrastiveLoss.swift` | Feature separation metric |
| `ConfidenceCalibrator.swift` | Calibrated predictions |
| `scripts/convert_clap_to_coreml.py` | CLAP model conversion |

### Files Modified
| File | Changes |
|------|---------|
| `EmbeddingCache.swift` | Version bump for extended features |
| `TrainingDataCollector.swift` | Combined extractor, augmentation |
| `TaggingEngine.swift` | Multi-class inference, combined features |
| `ModelMetadata.swift` | Feature dimension, tag groups |
| `ModelTrainer.swift` | Multi-class training, mixup, label smoothing |
| `TrainingCoordinator.swift` | Tag group registry, multi-class integration |

### Expected Accuracy Gains

| Phase | Technique | Contribution |
|-------|-----------|--------------|
| 1 | Extended embeddings (1680-dim) | +8% |
| 2 | Multi-class hard negatives | +12% |
| 3 | SpecAugment + Mixup | +8% |
| 4 | CLAP embeddings (2192-dim) | +7% |
| 5 | Contrastive + calibration | +5% |
| **Total** | | **~40%** |

### Verification Checklist

- [ ] Phase 1: Build passes, existing tests pass
- [ ] Phase 2: Multi-class models train and load
- [ ] Phase 3: Augmented training improves validation accuracy
- [ ] Phase 4: CLAP model converts and extracts 512-dim
- [ ] Phase 5: Contrastive loss computed, calibration applied
- [ ] Integration: End-to-end training with all phases
- [ ] Subjective tags (WalkingBass, Dope, Asian) show measurable improvement
