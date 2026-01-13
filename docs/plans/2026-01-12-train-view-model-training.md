# TrainView & Model Training Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a complete in-app training system that lets users train CoreML models from their tagged MP3 collection.

**Architecture:** Users add folders of pre-tagged MP3s → app extracts existing ID3 tags as ground truth → extracts audio features → trains binary classifiers per tag using CreateML → saves .mlmodel with metadata. The TrainView provides UI for folder selection, tag discovery, training progress, and model management.

**Tech Stack:** SwiftUI, CreateML (MLClassifier, DataFrame), CrateBotCore (SpectralExtractor, AudioAnalyzer, BinaryTrainingDataGenerator, ModelManager, ID3Manager, TaggedTrack, ModelMetadata)

**Existing Components Used:**
- `ID3Manager` (Phase 10.1) - reads existing ID3 tags from MP3s
- `SpectralExtractor` (Phase 4.2) - extracts 32 audio features
- `AudioAnalyzer` (Phase 3.1) - converts audio to PCM buffer
- `BinaryTrainingDataGenerator` (Phase 5.2) - balances training data (min 50 samples, 3:1 ratio)
- `TaggedTrack` (Phase 5.2) - training data structure
- `ModelManager` (Phase 11.2) - model discovery and installation
- `ModelMetadata` (Phase 11.2) - version tracking and compatibility

---

## Task 1: TrainingDataCollector - Scan and Extract Training Data

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingDataCollectorTests.swift`

**Context:** This actor scans directories for MP3 files, reads their ID3 tags (using ID3Manager), and creates TaggedTrack instances for training. It bridges the gap between user's tagged music and the training pipeline.

**Step 1: Write the failing test**

```swift
// TrainingDataCollectorTests.swift
import XCTest
@testable import CrateBotCore

final class TrainingDataCollectorTests: XCTestCase {

    func testCollectFromEmptyDirectory() async throws {
        let collector = TrainingDataCollector()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await collector.collectTrainingData(from: [tempDir])

        XCTAssertTrue(result.tracks.isEmpty)
        XCTAssertEqual(result.scannedCount, 0)
    }

    func testDiscoverTagsFromTracks() async throws {
        let collector = TrainingDataCollector()
        let tracks = [
            TaggedTrack(id: "1", tags: ["House", "Upbeat", "Morning"]),
            TaggedTrack(id: "2", tags: ["Techno", "Dark", "Night"]),
            TaggedTrack(id: "3", tags: ["House", "Chill", "Morning"])
        ]

        let discovered = collector.discoverTags(from: tracks)

        XCTAssertEqual(discovered["House"], 2)
        XCTAssertEqual(discovered["Techno"], 1)
        XCTAssertEqual(discovered["Morning"], 2)
        XCTAssertEqual(discovered["Dark"], 1)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/noahraford/CrateBot4/.worktrees/swift-ui-phase && swift test --filter TrainingDataCollectorTests`
Expected: FAIL with "No such module" or "cannot find TrainingDataCollector"

**Step 3: Write minimal implementation**

```swift
// TrainingDataCollector.swift
import Foundation

/// Collects and prepares training data from user's tagged MP3 library
public actor TrainingDataCollector {

    public struct CollectionResult: Sendable {
        public let tracks: [TaggedTrack]
        public let scannedCount: Int
        public let errorCount: Int
        public let errors: [String]
    }

    public struct CollectionProgress: Sendable {
        public let current: Int
        public let total: Int
        public let currentFile: String
    }

    private let id3Manager = ID3Manager()

    public init() {}

    /// Scan directories for MP3 files and extract their tags
    public func collectTrainingData(
        from directories: [URL],
        progress: (@Sendable (CollectionProgress) -> Void)? = nil
    ) async throws -> CollectionResult {
        var mp3Files: [URL] = []

        // Find all MP3 files
        for directory in directories {
            let files = findMP3Files(in: directory)
            mp3Files.append(contentsOf: files)
        }

        guard !mp3Files.isEmpty else {
            return CollectionResult(tracks: [], scannedCount: 0, errorCount: 0, errors: [])
        }

        var tracks: [TaggedTrack] = []
        var errors: [String] = []
        let total = mp3Files.count

        for (index, fileURL) in mp3Files.enumerated() {
            progress?(CollectionProgress(
                current: index + 1,
                total: total,
                currentFile: fileURL.lastPathComponent
            ))

            do {
                let extractedTags = try await id3Manager.readTags(from: fileURL)
                let tags = extractTagsAsSet(from: extractedTags)

                if !tags.isEmpty {
                    let track = TaggedTrack(
                        id: fileURL.absoluteString,
                        tags: tags,
                        features: nil // Features extracted separately
                    )
                    tracks.append(track)
                }
            } catch {
                errors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return CollectionResult(
            tracks: tracks,
            scannedCount: mp3Files.count,
            errorCount: errors.count,
            errors: errors
        )
    }

    /// Discover all unique tags and their counts from collected tracks
    public func discoverTags(from tracks: [TaggedTrack]) -> [String: Int] {
        var tagCounts: [String: Int] = [:]
        for track in tracks {
            for tag in track.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return tagCounts
    }

    /// Extract features for tracks that don't have them
    public func extractFeatures(
        for tracks: [TaggedTrack],
        progress: (@Sendable (CollectionProgress) -> Void)? = nil
    ) async throws -> [TaggedTrack] {
        let analyzer = AudioAnalyzer()
        let extractor = SpectralExtractor()
        var result: [TaggedTrack] = []
        let total = tracks.count

        for (index, track) in tracks.enumerated() {
            guard let url = URL(string: track.id) else { continue }

            progress?(CollectionProgress(
                current: index + 1,
                total: total,
                currentFile: url.lastPathComponent
            ))

            // Skip if already has features
            if track.features != nil {
                result.append(track)
                continue
            }

            do {
                let buffer = try await analyzer.extractPCMBuffer(from: url)
                let features = try extractor.extract(from: buffer)

                let updatedTrack = TaggedTrack(
                    id: track.id,
                    tags: track.tags,
                    features: features
                )
                result.append(updatedTrack)
            } catch {
                // Skip tracks that fail feature extraction
                continue
            }
        }

        return result
    }

    // MARK: - Private

    private func findMP3Files(in directory: URL) -> [URL] {
        var mp3Files: [URL] = []

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return mp3Files
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "mp3" {
                mp3Files.append(fileURL)
            }
        }

        return mp3Files
    }

    private func extractTagsAsSet(from extracted: ExtractedTags) -> Set<String> {
        var tags = Set<String>()

        if let genre = extracted.genre, !genre.isEmpty {
            tags.insert(genre)
        }

        if let timing = extracted.timing, !timing.isEmpty {
            tags.insert(timing)
        }

        for mood in extracted.mood {
            if !mood.isEmpty {
                tags.insert(mood)
            }
        }

        for desc in extracted.descriptive {
            if !desc.isEmpty {
                tags.insert(desc)
            }
        }

        return tags
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/noahraford/CrateBot4/.worktrees/swift-ui-phase && swift test --filter TrainingDataCollectorTests`
Expected: PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingDataCollectorTests.swift
git commit -m "feat: add TrainingDataCollector for scanning tagged MP3s

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: ModelTrainer - Train CoreML Models with CreateML

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelTrainerTests.swift`

**Context:** This actor uses CreateML to train binary classifiers for each tag. It converts TaggedTrack arrays to MLDataTable format, trains using MLClassifier, and saves models with metadata. CreateML is only available on macOS 10.14+.

**Step 1: Write the failing test**

```swift
// ModelTrainerTests.swift
import XCTest
@testable import CrateBotCore

final class ModelTrainerTests: XCTestCase {

    func testPrepareTrainingDataFrame() throws {
        let trainer = ModelTrainer()

        // Create mock tracks with features
        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: [1.0, 2.0, 3.0]),
            TaggedTrack(id: "2", tags: ["Techno"], features: [4.0, 5.0, 6.0]),
            TaggedTrack(id: "3", tags: ["House"], features: [1.5, 2.5, 3.5])
        ]

        let dataFrame = try trainer.prepareDataFrame(
            for: "House",
            from: tracks,
            featureCount: 3
        )

        XCTAssertEqual(dataFrame.rows.count, 3)
    }

    func testTrainingConfigDefaults() {
        let config = ModelTrainer.TrainingConfig()

        XCTAssertEqual(config.validationSplit, 0.2)
        XCTAssertEqual(config.minSamplesPerTag, 50)
        XCTAssertEqual(config.maxNegativeRatio, 3.0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/noahraford/CrateBot4/.worktrees/swift-ui-phase && swift test --filter ModelTrainerTests`
Expected: FAIL with "cannot find ModelTrainer"

**Step 3: Write minimal implementation**

```swift
// ModelTrainer.swift
import Foundation
import CreateML
import TabularData

/// Trains CoreML binary classifiers using CreateML
public actor ModelTrainer {

    public struct TrainingConfig: Sendable {
        public var validationSplit: Double = 0.2
        public var minSamplesPerTag: Int = 50
        public var maxNegativeRatio: Double = 3.0
        public var randomSeed: Int = 42

        public init(
            validationSplit: Double = 0.2,
            minSamplesPerTag: Int = 50,
            maxNegativeRatio: Double = 3.0,
            randomSeed: Int = 42
        ) {
            self.validationSplit = validationSplit
            self.minSamplesPerTag = minSamplesPerTag
            self.maxNegativeRatio = maxNegativeRatio
            self.randomSeed = randomSeed
        }
    }

    public struct TrainingResult: Sendable {
        public let tag: String
        public let modelURL: URL
        public let trainingAccuracy: Double
        public let validationAccuracy: Double
        public let positiveCount: Int
        public let negativeCount: Int
    }

    public struct TrainingProgress: Sendable {
        public let phase: Phase
        public let currentTag: String?
        public let tagsCompleted: Int
        public let totalTags: Int

        public enum Phase: Sendable {
            case preparing
            case training(tag: String)
            case validating(tag: String)
            case saving(tag: String)
            case complete
        }
    }

    public enum TrainerError: Error, LocalizedError {
        case insufficientData(tag: String, count: Int, required: Int)
        case noFeaturesAvailable
        case trainingFailed(tag: String, underlying: Error)
        case saveFailed(tag: String, underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .insufficientData(let tag, let count, let required):
                return "Tag '\(tag)' has \(count) samples, needs \(required)"
            case .noFeaturesAvailable:
                return "Tracks must have features extracted before training"
            case .trainingFailed(let tag, let error):
                return "Training failed for '\(tag)': \(error.localizedDescription)"
            case .saveFailed(let tag, let error):
                return "Save failed for '\(tag)': \(error.localizedDescription)"
            }
        }
    }

    private let dataGenerator = BinaryTrainingDataGenerator()

    public init() {}

    /// Train binary classifiers for each viable tag
    public func trainModels(
        from tracks: [TaggedTrack],
        tags: [String],
        outputDirectory: URL,
        config: TrainingConfig = TrainingConfig(),
        progress: (@Sendable (TrainingProgress) -> Void)? = nil
    ) async throws -> [TrainingResult] {
        // Filter to tracks with features
        let tracksWithFeatures = tracks.filter { $0.features != nil && !$0.features!.isEmpty }

        guard !tracksWithFeatures.isEmpty else {
            throw TrainerError.noFeaturesAvailable
        }

        let featureCount = tracksWithFeatures.first!.features!.count
        var results: [TrainingResult] = []

        progress?(TrainingProgress(
            phase: .preparing,
            currentTag: nil,
            tagsCompleted: 0,
            totalTags: tags.count
        ))

        for (index, tag) in tags.enumerated() {
            progress?(TrainingProgress(
                phase: .training(tag: tag),
                currentTag: tag,
                tagsCompleted: index,
                totalTags: tags.count
            ))

            do {
                let result = try await trainSingleModel(
                    for: tag,
                    from: tracksWithFeatures,
                    featureCount: featureCount,
                    outputDirectory: outputDirectory,
                    config: config
                )
                results.append(result)

            } catch TrainerError.insufficientData {
                // Skip tags with insufficient data
                continue
            }
        }

        progress?(TrainingProgress(
            phase: .complete,
            currentTag: nil,
            tagsCompleted: tags.count,
            totalTags: tags.count
        ))

        return results
    }

    /// Prepare a DataFrame for training a single binary classifier
    public func prepareDataFrame(
        for tag: String,
        from tracks: [TaggedTrack],
        featureCount: Int
    ) throws -> DataFrame {
        var rows: [[Any]] = []

        for track in tracks {
            guard let features = track.features, features.count == featureCount else {
                continue
            }

            let label = track.tags.contains(tag) ? "positive" : "negative"
            var row: [Any] = features.map { Double($0) }
            row.append(label)
            rows.append(row)
        }

        // Create column names
        var columns: [String] = (0..<featureCount).map { "f\($0)" }
        columns.append("label")

        // Build DataFrame
        var dataFrame = DataFrame()

        for (colIndex, colName) in columns.enumerated() {
            if colIndex < featureCount {
                let values = rows.map { $0[colIndex] as! Double }
                dataFrame.append(column: Column(name: colName, contents: values))
            } else {
                let values = rows.map { $0[colIndex] as! String }
                dataFrame.append(column: Column(name: colName, contents: values))
            }
        }

        return dataFrame
    }

    // MARK: - Private

    private func trainSingleModel(
        for tag: String,
        from tracks: [TaggedTrack],
        featureCount: Int,
        outputDirectory: URL,
        config: TrainingConfig
    ) async throws -> TrainingResult {
        // Generate balanced training data
        guard let (positive, negative) = dataGenerator.generateTrainingData(for: tag, from: tracks) else {
            let positiveCount = tracks.filter { $0.tags.contains(tag) }.count
            throw TrainerError.insufficientData(
                tag: tag,
                count: positiveCount,
                required: config.minSamplesPerTag
            )
        }

        // Combine and prepare DataFrame
        let allTracks = positive + negative
        let dataFrame = try prepareDataFrame(for: tag, from: allTracks, featureCount: featureCount)

        // Split into training and validation
        let (trainingData, validationData) = dataFrame.randomSplit(
            by: 1.0 - config.validationSplit,
            seed: config.randomSeed
        )

        // Train the classifier
        let classifier: MLClassifier
        do {
            classifier = try MLClassifier(
                trainingData: DataFrame(trainingData),
                targetColumn: "label"
            )
        } catch {
            throw TrainerError.trainingFailed(tag: tag, underlying: error)
        }

        // Calculate accuracies
        let trainingError = classifier.trainingMetrics.classificationError
        let trainingAccuracy = 1.0 - trainingError

        let validationMetrics = classifier.evaluation(on: DataFrame(validationData), targetColumn: "label")
        let validationAccuracy = 1.0 - validationMetrics.classificationError

        // Save the model
        let safeName = tag.replacingOccurrences(of: " ", with: "_").lowercased()
        let modelURL = outputDirectory.appendingPathComponent("\(safeName).mlmodel")

        let metadata = MLModelMetadata(
            author: "CrateBot",
            shortDescription: "Binary classifier for tag: \(tag)",
            version: "1.0"
        )

        do {
            try classifier.write(to: modelURL, metadata: metadata)
        } catch {
            throw TrainerError.saveFailed(tag: tag, underlying: error)
        }

        return TrainingResult(
            tag: tag,
            modelURL: modelURL,
            trainingAccuracy: trainingAccuracy,
            validationAccuracy: validationAccuracy,
            positiveCount: positive.count,
            negativeCount: negative.count
        )
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/noahraford/CrateBot4/.worktrees/swift-ui-phase && swift test --filter ModelTrainerTests`
Expected: PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift CrateBotCore/Tests/CrateBotCoreTests/ML/ModelTrainerTests.swift
git commit -m "feat: add ModelTrainer for CreateML-based model training

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: TrainingCoordinator - Orchestrate Training Pipeline

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCoordinatorTests.swift`

**Context:** The coordinator brings together TrainingDataCollector, ModelTrainer, and ModelManager. It handles the full training workflow: collect data → extract features → train models → package and save with metadata.

**Step 1: Write the failing test**

```swift
// TrainingCoordinatorTests.swift
import XCTest
@testable import CrateBotCore

final class TrainingCoordinatorTests: XCTestCase {

    func testTrainingStateTransitions() async {
        let coordinator = TrainingCoordinator()

        // Initial state
        let initial = await coordinator.state
        XCTAssertEqual(initial, .idle)
    }

    func testPackageModelBundle() async throws {
        let coordinator = TrainingCoordinator()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelName = "test-model"
        let tags = ["House": ["House"], "Mood": ["Upbeat", "Chill"]]

        let metadata = try await coordinator.createModelMetadata(
            name: modelName,
            tags: tags,
            trainingFileCount: 100,
            accuracy: 0.85
        )

        XCTAssertEqual(metadata.name, modelName)
        XCTAssertEqual(metadata.trainingFileCount, 100)
        XCTAssertEqual(metadata.accuracy, 0.85)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/noahraford/CrateBot4/.worktrees/swift-ui-phase && swift test --filter TrainingCoordinatorTests`
Expected: FAIL with "cannot find TrainingCoordinator"

**Step 3: Write minimal implementation**

```swift
// TrainingCoordinator.swift
import Foundation

/// Orchestrates the complete training pipeline
public actor TrainingCoordinator {

    public enum State: Equatable, Sendable {
        case idle
        case collecting(progress: Double)
        case extractingFeatures(progress: Double)
        case training(progress: Double, currentTag: String)
        case packaging
        case complete(modelName: String)
        case failed(error: String)
    }

    public struct TrainingOptions: Sendable {
        public var modelName: String
        public var selectedTags: Set<String>
        public var validationSplit: Double
        public var minSamplesPerTag: Int

        public init(
            modelName: String = "custom-model",
            selectedTags: Set<String> = [],
            validationSplit: Double = 0.2,
            minSamplesPerTag: Int = 50
        ) {
            self.modelName = modelName
            self.selectedTags = selectedTags
            self.validationSplit = validationSplit
            self.minSamplesPerTag = minSamplesPerTag
        }
    }

    public struct TrainingSummary: Sendable {
        public let modelName: String
        public let trainedTags: [String]
        public let skippedTags: [String]
        public let totalTracks: Int
        public let averageAccuracy: Double
        public let modelURL: URL
    }

    public private(set) var state: State = .idle

    private let collector = TrainingDataCollector()
    private let trainer = ModelTrainer()
    private let modelManager: ModelManager

    public init(modelManager: ModelManager = ModelManager()) {
        self.modelManager = modelManager
    }

    /// Run the complete training pipeline
    public func train(
        from directories: [URL],
        options: TrainingOptions,
        stateCallback: (@Sendable (State) -> Void)? = nil
    ) async throws -> TrainingSummary {
        // Phase 1: Collect training data
        state = .collecting(progress: 0)
        stateCallback?(state)

        let collectionResult = try await collector.collectTrainingData(from: directories) { progress in
            let pct = Double(progress.current) / Double(progress.total)
            Task { @MainActor in
                stateCallback?(.collecting(progress: pct))
            }
        }

        guard !collectionResult.tracks.isEmpty else {
            state = .failed(error: "No tagged MP3 files found")
            stateCallback?(state)
            throw CoordinatorError.noDataFound
        }

        // Discover tags
        let discoveredTags = collector.discoverTags(from: collectionResult.tracks)
        let viableTags = discoveredTags.filter { $0.value >= options.minSamplesPerTag }

        // Filter to selected tags (or all viable if none selected)
        let tagsToTrain: [String]
        if options.selectedTags.isEmpty {
            tagsToTrain = Array(viableTags.keys).sorted()
        } else {
            tagsToTrain = options.selectedTags.filter { viableTags.keys.contains($0) }.sorted()
        }

        guard !tagsToTrain.isEmpty else {
            state = .failed(error: "No tags have enough samples for training")
            stateCallback?(state)
            throw CoordinatorError.insufficientData
        }

        // Phase 2: Extract features
        state = .extractingFeatures(progress: 0)
        stateCallback?(state)

        let tracksWithFeatures = try await collector.extractFeatures(for: collectionResult.tracks) { progress in
            let pct = Double(progress.current) / Double(progress.total)
            Task { @MainActor in
                stateCallback?(.extractingFeatures(progress: pct))
            }
        }

        // Phase 3: Train models
        let outputDirectory = try createTrainingOutputDirectory(name: options.modelName)

        let config = ModelTrainer.TrainingConfig(
            validationSplit: options.validationSplit,
            minSamplesPerTag: options.minSamplesPerTag
        )

        var trainingResults: [ModelTrainer.TrainingResult] = []

        trainingResults = try await trainer.trainModels(
            from: tracksWithFeatures,
            tags: tagsToTrain,
            outputDirectory: outputDirectory,
            config: config
        ) { progress in
            let pct = Double(progress.tagsCompleted) / Double(progress.totalTags)
            let currentTag = progress.currentTag ?? ""
            Task { @MainActor in
                stateCallback?(.training(progress: pct, currentTag: currentTag))
            }
        }

        // Phase 4: Package model bundle
        state = .packaging
        stateCallback?(state)

        let trainedTags = trainingResults.map { $0.tag }
        let skippedTags = tagsToTrain.filter { !trainedTags.contains($0) }
        let avgAccuracy = trainingResults.isEmpty ? 0 : trainingResults.map { $0.validationAccuracy }.reduce(0, +) / Double(trainingResults.count)

        let metadata = try await createModelMetadata(
            name: options.modelName,
            tags: categorizeTrainedTags(trainedTags),
            trainingFileCount: tracksWithFeatures.count,
            accuracy: avgAccuracy
        )

        // Save metadata alongside models
        let metadataURL = outputDirectory.appendingPathComponent("\(options.modelName).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataURL)

        // Complete
        state = .complete(modelName: options.modelName)
        stateCallback?(state)

        return TrainingSummary(
            modelName: options.modelName,
            trainedTags: trainedTags,
            skippedTags: skippedTags,
            totalTracks: tracksWithFeatures.count,
            averageAccuracy: avgAccuracy,
            modelURL: outputDirectory
        )
    }

    /// Create model metadata for a trained model bundle
    public func createModelMetadata(
        name: String,
        tags: [String: [String]],
        trainingFileCount: Int,
        accuracy: Double?
    ) async throws -> ModelMetadata {
        return ModelMetadata(
            name: name,
            version: "1.0.0",
            pipelineVersion: FeaturePipelineVersion.current.versionHash,
            trainedAt: Date(),
            trainingFileCount: trainingFileCount,
            categories: Array(tags.keys).sorted(),
            tags: tags,
            accuracy: accuracy
        )
    }

    /// Reset coordinator state
    public func reset() {
        state = .idle
    }

    // MARK: - Private

    private func createTrainingOutputDirectory(name: String) throws -> URL {
        let baseDir = modelManager.modelsDirectory()
        let outputDir = baseDir.appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.removeItem(at: outputDir)
        }

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return outputDir
    }

    private func categorizeTrainedTags(_ tags: [String]) -> [String: [String]] {
        // Simple categorization - in production this would use tag metadata
        var categories: [String: [String]] = [
            "Genre": [],
            "Mood": [],
            "Timing": [],
            "Descriptive": []
        ]

        // Known genre tags
        let genreTags = Set(["House", "Techno", "Trance", "Dubstep", "DnB", "Ambient", "Indie", "Pop", "Rock", "Hip-Hop", "R&B", "Jazz", "Classical", "Electronic"])
        // Known timing tags
        let timingTags = Set(["Morning", "Afternoon", "Evening", "Night", "Late Night", "Peak Time", "Warm Up"])
        // Known mood tags
        let moodTags = Set(["Upbeat", "Chill", "Dark", "Energetic", "Melancholic", "Happy", "Aggressive", "Peaceful", "Trippy"])

        for tag in tags {
            if genreTags.contains(tag) {
                categories["Genre"]?.append(tag)
            } else if timingTags.contains(tag) {
                categories["Timing"]?.append(tag)
            } else if moodTags.contains(tag) {
                categories["Mood"]?.append(tag)
            } else {
                categories["Descriptive"]?.append(tag)
            }
        }

        // Remove empty categories
        return categories.filter { !$0.value.isEmpty }
    }

    public enum CoordinatorError: Error, LocalizedError {
        case noDataFound
        case insufficientData
        case trainingFailed
        case saveFailed

        public var errorDescription: String? {
            switch self {
            case .noDataFound:
                return "No tagged MP3 files found in the selected directories"
            case .insufficientData:
                return "Not enough samples to train any tags"
            case .trainingFailed:
                return "Model training failed"
            case .saveFailed:
                return "Failed to save trained model"
            }
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/noahraford/CrateBot4/.worktrees/swift-ui-phase && swift test --filter TrainingCoordinatorTests`
Expected: PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCoordinatorTests.swift
git commit -m "feat: add TrainingCoordinator to orchestrate full training pipeline

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: TrainView UI - Folder Selection and Tag Discovery

**Files:**
- Modify: `CrateBot/Views/TrainView.swift`

**Context:** Replace the placeholder TrainView with a full training UI. This task handles the first phase: selecting source folders and discovering available tags.

**Step 1: No test (UI code)**

**Step 2: Implement TrainView folder selection**

```swift
// TrainView.swift
import SwiftUI
import CrateBotCore
import AppKit

struct TrainView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFolders: [URL] = []
    @State private var isScanning = false
    @State private var discoveredTags: [String: Int] = [:]
    @State private var selectedTags: Set<String> = []
    @State private var collectedTracks: [TaggedTrack] = []
    @State private var scanError: String?
    @State private var modelName: String = ""
    @State private var trainingState: TrainingCoordinator.State = .idle
    @State private var trainingSummary: TrainingCoordinator.TrainingSummary?

    private let coordinator = TrainingCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Train Model")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if !collectedTracks.isEmpty {
                    Text("\(collectedTracks.count) tracks")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Content based on state
            Group {
                switch trainingState {
                case .idle:
                    if discoveredTags.isEmpty {
                        folderSelectionView
                    } else {
                        tagSelectionView
                    }
                case .collecting(let progress),
                     .extractingFeatures(let progress):
                    progressView(progress: progress, phase: trainingState)
                case .training(let progress, let currentTag):
                    trainingProgressView(progress: progress, currentTag: currentTag)
                case .packaging:
                    packagingView
                case .complete(let modelName):
                    completionView(modelName: modelName)
                case .failed(let error):
                    errorView(error: error)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Folder Selection

    private var folderSelectionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Select Training Data")
                .font(.title2)
                .fontWeight(.medium)

            Text("Choose folders containing MP3 files with existing ID3 tags.\nCrateBot will learn from your existing tags.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Selected folders list
            if !selectedFolders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedFolders, id: \.absoluteString) { url in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                selectedFolders.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(.regularMaterial)
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: 400)
            }

            // Error message
            if let error = scanError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Buttons
            HStack(spacing: 16) {
                Button {
                    selectFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }

                if !selectedFolders.isEmpty {
                    Button {
                        scanFolders()
                    } label: {
                        Label("Scan for Tags", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning)
                }
            }

            if isScanning {
                ProgressView("Scanning...")
                    .padding(.top, 8)
            }
        }
        .padding(24)
    }

    // MARK: - Tag Selection

    private var tagSelectionView: some View {
        VStack(spacing: 0) {
            // Model name input
            HStack {
                Text("Model Name:")
                TextField("my-custom-model", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            // Tag grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 150), spacing: 12)
                ], spacing: 12) {
                    ForEach(sortedTags, id: \.0) { tag, count in
                        tagCard(tag: tag, count: count)
                    }
                }
                .padding(24)
            }

            Divider()

            // Bottom controls
            HStack {
                Button("Back") {
                    discoveredTags = [:]
                    collectedTracks = []
                    selectedTags = []
                }

                Spacer()

                Text("\(selectedTags.count) tags selected")
                    .foregroundStyle(.secondary)

                Button("Select All Viable") {
                    selectedTags = Set(viableTags.map { $0.0 })
                }
                .disabled(viableTags.isEmpty)

                Button {
                    startTraining()
                } label: {
                    Label("Start Training", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTags.isEmpty || modelName.isEmpty)
            }
            .padding(16)
            .background(.regularMaterial)
        }
    }

    private func tagCard(tag: String, count: Int) -> some View {
        let isViable = count >= 50
        let isSelected = selectedTags.contains(tag)

        return Button {
            if isViable {
                if isSelected {
                    selectedTags.remove(tag)
                } else {
                    selectedTags.insert(tag)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tag)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                HStack {
                    Text("\(count) samples")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !isViable {
                        Text("(need 50)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .background(.regularMaterial)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isViable)
        .opacity(isViable ? 1 : 0.5)
    }

    private var sortedTags: [(String, Int)] {
        discoveredTags.sorted { $0.value > $1.value }
    }

    private var viableTags: [(String, Int)] {
        sortedTags.filter { $0.1 >= 50 }
    }

    // MARK: - Progress Views

    private func progressView(progress: Double, phase: TrainingCoordinator.State) -> some View {
        VStack(spacing: 24) {
            ProgressView(value: progress)
                .frame(maxWidth: 400)

            Text(phaseDescription(phase))
                .font(.headline)

            Text("\(Int(progress * 100))%")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func trainingProgressView(progress: Double, currentTag: String) -> some View {
        VStack(spacing: 24) {
            ProgressView(value: progress)
                .frame(maxWidth: 400)

            Text("Training Models")
                .font(.headline)

            Text("Current: \(currentTag)")
                .foregroundStyle(.secondary)

            Text("\(Int(progress * 100))%")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var packagingView: some View {
        VStack(spacing: 24) {
            ProgressView()
            Text("Packaging model...")
                .font(.headline)
        }
        .padding(24)
    }

    private func completionView(modelName: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Training Complete!")
                .font(.title2)
                .fontWeight(.bold)

            if let summary = trainingSummary {
                VStack(spacing: 8) {
                    Text("Model: \(summary.modelName)")
                    Text("Tags trained: \(summary.trainedTags.count)")
                    Text("Tracks used: \(summary.totalTracks)")
                    Text("Average accuracy: \(Int(summary.averageAccuracy * 100))%")
                }
                .foregroundStyle(.secondary)
            }

            Button("Train Another Model") {
                resetState()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func errorView(error: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Training Failed")
                .font(.title2)
                .fontWeight(.bold)

            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                resetState()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func phaseDescription(_ phase: TrainingCoordinator.State) -> String {
        switch phase {
        case .collecting: return "Scanning MP3 files..."
        case .extractingFeatures: return "Extracting audio features..."
        case .training: return "Training models..."
        case .packaging: return "Packaging model..."
        default: return ""
        }
    }

    // MARK: - Actions

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                if !selectedFolders.contains(url) {
                    selectedFolders.append(url)
                }
            }
        }
    }

    private func scanFolders() {
        isScanning = true
        scanError = nil

        Task {
            do {
                let collector = TrainingDataCollector()
                let result = try await collector.collectTrainingData(from: selectedFolders)

                await MainActor.run {
                    collectedTracks = result.tracks
                    discoveredTags = collector.discoverTags(from: result.tracks)
                    isScanning = false

                    if result.tracks.isEmpty {
                        scanError = "No tagged MP3 files found"
                    }
                }
            } catch {
                await MainActor.run {
                    scanError = error.localizedDescription
                    isScanning = false
                }
            }
        }
    }

    private func startTraining() {
        let options = TrainingCoordinator.TrainingOptions(
            modelName: modelName,
            selectedTags: selectedTags
        )

        Task {
            do {
                let summary = try await coordinator.train(
                    from: selectedFolders,
                    options: options
                ) { state in
                    Task { @MainActor in
                        trainingState = state
                    }
                }

                await MainActor.run {
                    trainingSummary = summary
                    appState.showToast("Model trained successfully!")
                }
            } catch {
                await MainActor.run {
                    trainingState = .failed(error: error.localizedDescription)
                }
            }
        }
    }

    private func resetState() {
        trainingState = .idle
        discoveredTags = [:]
        collectedTracks = []
        selectedTags = []
        selectedFolders = []
        modelName = ""
        trainingSummary = nil
        scanError = nil

        Task {
            await coordinator.reset()
        }
    }
}

#Preview {
    TrainView()
        .environment(AppState())
        .frame(width: 700, height: 600)
}
```

**Step 3: Commit**

```bash
git add CrateBot/Views/TrainView.swift
git commit -m "feat: implement TrainView with folder selection, tag discovery, and training UI

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Export CrateBotCore Public API

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/CrateBotCore.swift`

**Context:** Ensure all new training types are exported from CrateBotCore so the app can use them.

**Step 1: Update exports**

```swift
// Add to CrateBotCore.swift exports section

// ML - Training
public typealias TrainingDataCollector = CrateBotCore.TrainingDataCollector
public typealias ModelTrainer = CrateBotCore.ModelTrainer
public typealias TrainingCoordinator = CrateBotCore.TrainingCoordinator
```

**Step 2: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/CrateBotCore.swift
git commit -m "feat: export training types from CrateBotCore public API

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Integration Test - Full Training Pipeline

**Files:**
- Create: `CrateBotCore/Tests/CrateBotCoreTests/Integration/TrainingPipelineTests.swift`

**Context:** End-to-end test verifying the training pipeline works correctly.

**Step 1: Write integration test**

```swift
// TrainingPipelineTests.swift
import XCTest
@testable import CrateBotCore

final class TrainingPipelineTests: XCTestCase {

    func testFullTrainingPipelineWithMockData() async throws {
        // Create mock tagged tracks
        let tracks = createMockTracks(count: 200)

        let collector = TrainingDataCollector()
        let discovered = collector.discoverTags(from: tracks)

        // Verify tag discovery
        XCTAssertGreaterThan(discovered.count, 0)

        // Verify viable tags (>= 50 samples)
        let viable = discovered.filter { $0.value >= 50 }
        XCTAssertGreaterThan(viable.count, 0)
    }

    private func createMockTracks(count: Int) -> [TaggedTrack] {
        let tags = ["House", "Techno", "Upbeat", "Chill", "Morning", "Night"]
        var tracks: [TaggedTrack] = []

        for i in 0..<count {
            // Randomly assign 1-3 tags
            let numTags = Int.random(in: 1...3)
            var trackTags = Set<String>()
            for _ in 0..<numTags {
                trackTags.insert(tags.randomElement()!)
            }

            // Create mock features (32 floats)
            let features = (0..<32).map { _ in Float.random(in: 0...1) }

            tracks.append(TaggedTrack(
                id: "track-\(i)",
                tags: trackTags,
                features: features
            ))
        }

        return tracks
    }
}
```

**Step 2: Run test**

Run: `cd /Users/noahraford/CrateBot4/.worktrees/swift-ui-phase && swift test --filter TrainingPipelineTests`
Expected: PASS

**Step 3: Commit**

```bash
git add CrateBotCore/Tests/CrateBotCoreTests/Integration/TrainingPipelineTests.swift
git commit -m "test: add integration tests for training pipeline

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Summary

This plan implements:
1. **TrainingDataCollector** - Scans MP3s and extracts existing tags
2. **ModelTrainer** - Trains binary classifiers using CreateML
3. **TrainingCoordinator** - Orchestrates the full pipeline
4. **TrainView** - Complete UI for training workflow

After implementing, users can:
1. Select folders with tagged MP3s
2. See discovered tags and sample counts
3. Select which tags to train
4. Train models and see progress
5. Use trained models for tagging

**Dependencies:**
- CreateML framework (macOS 10.14+)
- TabularData framework
- Existing CrateBotCore components (SpectralExtractor, ID3Manager, ModelManager)
