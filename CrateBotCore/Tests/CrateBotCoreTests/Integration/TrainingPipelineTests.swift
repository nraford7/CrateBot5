import XCTest
@testable import CrateBotCore

final class TrainingPipelineTests: XCTestCase {

    // MARK: - Mock Data Helpers

    /// Creates mock tracks with random tags and optional features
    private func createMockTracks(count: Int, withFeatures: Bool = false, featureCount: Int = 32) -> [TaggedTrack] {
        let tags = ["House", "Techno", "Upbeat", "Chill", "Morning", "Night"]
        var tracks: [TaggedTrack] = []

        for i in 0..<count {
            let numTags = Int.random(in: 1...3)
            var trackTags = Set<String>()
            for _ in 0..<numTags {
                trackTags.insert(tags.randomElement()!)
            }

            let features: [Float]? = withFeatures
                ? (0..<featureCount).map { _ in Float.random(in: 0...1) }
                : nil

            tracks.append(TaggedTrack(
                id: "track-\(i)",
                tags: trackTags,
                features: features
            ))
        }

        return tracks
    }

    /// Creates mock tracks with a guaranteed distribution of specific tags
    private func createMockTracksWithDistribution(
        tagCounts: [String: Int],
        featureCount: Int = 32
    ) -> [TaggedTrack] {
        var tracks: [TaggedTrack] = []
        var trackId = 0

        for (tag, count) in tagCounts {
            for _ in 0..<count {
                let features = (0..<featureCount).map { _ in Float.random(in: 0...1) }
                tracks.append(TaggedTrack(
                    id: "track-\(trackId)",
                    tags: [tag],
                    features: features
                ))
                trackId += 1
            }
        }

        return tracks.shuffled()
    }

    // MARK: - TrainingDataCollector Tag Discovery Tests

    func testTrainingDataCollectorDiscoversTags() async {
        let collector = TrainingDataCollector()
        let tracks = createMockTracks(count: 200)

        let discovered = await collector.discoverTags(from: tracks)

        // Should discover tags from the mock tracks
        XCTAssertGreaterThan(discovered.count, 0)
        XCTAssertLessThanOrEqual(discovered.count, 6) // Max 6 unique tags in our mock

        // All discovered tags should have positive counts
        for (tag, count) in discovered {
            XCTAssertGreaterThan(count, 0, "Tag '\(tag)' should have positive count")
        }
    }

    func testDiscoverTagsCountsAreAccurate() async {
        let collector = TrainingDataCollector()

        // Create tracks with known distribution
        let tracks = [
            TaggedTrack(id: "1", tags: ["House", "Upbeat"]),
            TaggedTrack(id: "2", tags: ["House", "Chill"]),
            TaggedTrack(id: "3", tags: ["House"]),
            TaggedTrack(id: "4", tags: ["Techno", "Upbeat"]),
            TaggedTrack(id: "5", tags: ["Techno"]),
        ]

        let discovered = await collector.discoverTags(from: tracks)

        XCTAssertEqual(discovered["House"], 3)
        XCTAssertEqual(discovered["Techno"], 2)
        XCTAssertEqual(discovered["Upbeat"], 2)
        XCTAssertEqual(discovered["Chill"], 1)
    }

    // MARK: - Viable Tags Filtering Tests

    func testViableTagsFiltersBelowThreshold() {
        let generator = BinaryTrainingDataGenerator()

        // Create tracks with controlled distribution
        let tracks = createMockTracksWithDistribution(tagCounts: [
            "House": 60,    // Viable (>= 50)
            "Techno": 55,   // Viable (>= 50)
            "Chill": 30,    // Not viable (< 50)
            "Rare": 5,      // Not viable (< 50)
        ])

        let viable = generator.viableTags(from: tracks)

        XCTAssertEqual(viable.count, 2)
        XCTAssertNotNil(viable["House"])
        XCTAssertNotNil(viable["Techno"])
        XCTAssertNil(viable["Chill"])
        XCTAssertNil(viable["Rare"])
    }

    func testViableTagsAtExactThreshold() {
        let generator = BinaryTrainingDataGenerator()

        let tracks = createMockTracksWithDistribution(tagCounts: [
            "ExactlyFifty": 50,  // Exactly at threshold - should be viable
            "FortyNine": 49,     // Just below threshold - not viable
        ])

        let viable = generator.viableTags(from: tracks)

        XCTAssertEqual(viable.count, 1)
        XCTAssertNotNil(viable["ExactlyFifty"])
        XCTAssertNil(viable["FortyNine"])
    }

    // MARK: - ModelTrainer DataFrame Tests

    func testModelTrainerPrepareDataFrame() async throws {
        let trainer = ModelTrainer()
        let featureCount = 32
        let tracks = createMockTracks(count: 100, withFeatures: true, featureCount: featureCount)

        let dataFrame = try await trainer.prepareDataFrame(
            for: "House",
            from: tracks,
            featureCount: featureCount
        )

        // Should have featureCount columns + 1 label column
        XCTAssertEqual(dataFrame.columns.count, featureCount + 1)

        // Verify feature columns exist
        for i in 0..<featureCount {
            XCTAssertTrue(dataFrame.containsColumn("f\(i)"), "Missing feature column f\(i)")
        }

        // Verify label column exists
        XCTAssertTrue(dataFrame.containsColumn("label"))
    }

    func testModelTrainerDataFrameLabelsAreCorrect() async throws {
        let trainer = ModelTrainer()

        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: [1.0, 2.0, 3.0]),
            TaggedTrack(id: "2", tags: ["House", "Chill"], features: [4.0, 5.0, 6.0]),
            TaggedTrack(id: "3", tags: ["Techno"], features: [7.0, 8.0, 9.0]),
            TaggedTrack(id: "4", tags: ["Chill"], features: [10.0, 11.0, 12.0]),
        ]

        let dataFrame = try await trainer.prepareDataFrame(
            for: "House",
            from: tracks,
            featureCount: 3
        )

        let labels = dataFrame["label", String.self]
        let labelArray = Array(labels)

        // First two tracks have "House" tag
        XCTAssertEqual(labelArray[0], "positive")
        XCTAssertEqual(labelArray[1], "positive")
        // Last two tracks don't have "House" tag
        XCTAssertEqual(labelArray[2], "negative")
        XCTAssertEqual(labelArray[3], "negative")
    }

    // MARK: - TrainingCoordinator State Tests

    func testTrainingCoordinatorStartsIdle() async {
        let coordinator = TrainingCoordinator()
        let state = await coordinator.state
        XCTAssertEqual(state, .idle)
    }

    func testTrainingCoordinatorResetReturnsToIdle() async {
        let coordinator = TrainingCoordinator()

        await coordinator.reset()
        let state = await coordinator.state

        XCTAssertEqual(state, .idle)
    }

    // MARK: - BinaryTrainingDataGenerator Balancing Tests

    func testDataGeneratorProducesBalancedData() {
        let generator = BinaryTrainingDataGenerator()

        let tracks = createMockTracksWithDistribution(tagCounts: [
            "House": 60,
            "Other": 200,  // Many more negative samples
        ])

        guard let (positive, negative) = generator.generateTrainingData(for: "House", from: tracks) else {
            XCTFail("Should generate training data for House with 60 samples")
            return
        }

        // Should have all 60 positive samples
        XCTAssertEqual(positive.count, 60)

        // Negative samples should be capped at 3:1 ratio (60 * 3 = 180)
        XCTAssertLessThanOrEqual(negative.count, 180)
        XCTAssertGreaterThan(negative.count, 0)

        // Verify balancing ratio
        let ratio = Double(negative.count) / Double(positive.count)
        XCTAssertLessThanOrEqual(ratio, BinaryTrainingDataGenerator.maxNegativeRatio)
    }

    func testDataGeneratorReturnsNilForInsufficientPositives() {
        let generator = BinaryTrainingDataGenerator()

        let tracks = createMockTracksWithDistribution(tagCounts: [
            "Rare": 30,    // Below minimum of 50
            "Other": 100,
        ])

        let result = generator.generateTrainingData(for: "Rare", from: tracks)

        XCTAssertNil(result, "Should return nil when positive samples < 50")
    }

    // MARK: - Full Pipeline Integration Tests

    func testFullPipelineWithMockData() async {
        // Create a realistic mock dataset
        let tracks = createMockTracksWithDistribution(tagCounts: [
            "House": 80,
            "Techno": 70,
            "Upbeat": 60,
            "Chill": 55,
            "Morning": 30,  // Below threshold
            "Night": 20,    // Below threshold
        ])

        // Step 1: Discover tags using TrainingDataCollector
        let collector = TrainingDataCollector()
        let discovered = await collector.discoverTags(from: tracks)

        // Verify tag discovery
        XCTAssertEqual(discovered.count, 6)
        XCTAssertEqual(discovered["House"], 80)
        XCTAssertEqual(discovered["Techno"], 70)

        // Step 2: Filter to viable tags (>= 50 samples)
        let viable = discovered.filter { $0.value >= BinaryTrainingDataGenerator.minPositiveExamples }

        XCTAssertEqual(viable.count, 4)
        XCTAssertNotNil(viable["House"])
        XCTAssertNotNil(viable["Techno"])
        XCTAssertNotNil(viable["Upbeat"])
        XCTAssertNotNil(viable["Chill"])
        XCTAssertNil(viable["Morning"])
        XCTAssertNil(viable["Night"])

        // Step 3: Verify data generator can balance data for each viable tag
        let generator = BinaryTrainingDataGenerator()

        for tag in viable.keys {
            guard let (positive, negative) = generator.generateTrainingData(for: tag, from: tracks) else {
                XCTFail("Failed to generate training data for viable tag '\(tag)'")
                continue
            }

            // Positive count should match expected
            XCTAssertEqual(positive.count, viable[tag])

            // Negative samples should be properly balanced
            let maxNegatives = Int(Double(positive.count) * BinaryTrainingDataGenerator.maxNegativeRatio)
            XCTAssertLessThanOrEqual(negative.count, maxNegatives)
        }
    }

    func testPipelineWithTracksHavingFeatures() async throws {
        // Create tracks with features
        let tracks = createMockTracksWithDistribution(tagCounts: [
            "House": 60,
            "Techno": 55,
        ])

        let collector = TrainingDataCollector()
        let generator = BinaryTrainingDataGenerator()
        let trainer = ModelTrainer()

        // Discover and filter tags
        let discovered = await collector.discoverTags(from: tracks)
        let viable = discovered.filter { $0.value >= BinaryTrainingDataGenerator.minPositiveExamples }

        XCTAssertEqual(viable.count, 2)

        // Generate balanced data for first tag
        let firstTag = viable.keys.sorted().first!
        guard let (positive, negative) = generator.generateTrainingData(for: firstTag, from: tracks) else {
            XCTFail("Should generate training data")
            return
        }

        // Prepare DataFrame
        let allTracks = positive + negative
        let dataFrame = try await trainer.prepareDataFrame(
            for: firstTag,
            from: allTracks,
            featureCount: 32
        )

        // Verify DataFrame structure
        XCTAssertEqual(dataFrame.columns.count, 33) // 32 features + 1 label
        XCTAssertEqual(dataFrame.rows.count, allTracks.count)

        // Verify label distribution
        let labels = dataFrame["label", String.self]
        let positiveLabels = labels.filter { $0 == "positive" }.count
        let negativeLabels = labels.filter { $0 == "negative" }.count

        XCTAssertEqual(positiveLabels, positive.count)
        XCTAssertEqual(negativeLabels, negative.count)
    }

    // MARK: - Edge Cases

    func testEmptyTracksArray() async {
        let collector = TrainingDataCollector()
        let generator = BinaryTrainingDataGenerator()

        let discovered = await collector.discoverTags(from: [])
        XCTAssertTrue(discovered.isEmpty)

        let viable = generator.viableTags(from: [])
        XCTAssertTrue(viable.isEmpty)
    }

    func testTracksWithNoTags() async {
        let collector = TrainingDataCollector()

        let tracks = [
            TaggedTrack(id: "1", tags: Set<String>()),
            TaggedTrack(id: "2", tags: Set<String>()),
        ]

        let discovered = await collector.discoverTags(from: tracks)
        XCTAssertTrue(discovered.isEmpty)
    }

    func testTracksWithDuplicateTags() async {
        let collector = TrainingDataCollector()

        // Same track repeated (simulating duplicate detection scenario)
        let tracks = [
            TaggedTrack(id: "1", tags: ["House", "House"]),  // Set will dedupe
            TaggedTrack(id: "2", tags: ["House"]),
        ]

        let discovered = await collector.discoverTags(from: tracks)

        // Each track contributes 1 to the House count (Set deduplicates)
        XCTAssertEqual(discovered["House"], 2)
    }

    func testTracksWithMixedFeatureAvailability() async throws {
        let trainer = ModelTrainer()

        let tracks = [
            TaggedTrack(id: "1", tags: ["House"], features: [1.0, 2.0]),
            TaggedTrack(id: "2", tags: ["House"], features: nil),  // No features
            TaggedTrack(id: "3", tags: ["Techno"], features: [3.0, 4.0]),
            TaggedTrack(id: "4", tags: ["Techno"], features: []),  // Empty features
        ]

        let dataFrame = try await trainer.prepareDataFrame(
            for: "House",
            from: tracks,
            featureCount: 2
        )

        // Should only include tracks with valid features (id 1 and 3)
        XCTAssertEqual(dataFrame.rows.count, 2)
    }
}
