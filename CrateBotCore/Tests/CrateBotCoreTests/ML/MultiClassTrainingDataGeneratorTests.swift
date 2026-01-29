import XCTest
@testable import CrateBotCore

final class MultiClassTrainingDataGeneratorTests: XCTestCase {

    var registry: TagGroupRegistry!
    var generator: MultiClassTrainingDataGenerator!

    override func setUp() {
        super.setUp()
        registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy"])
        registry.addGroup(name: "Energy", tags: ["Low", "Medium", "High"])
        generator = MultiClassTrainingDataGenerator(registry: registry)
    }

    override func tearDown() {
        registry = nil
        generator = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeTrack(id: String, tags: [String], features: [Float]? = [1.0, 2.0, 3.0]) -> TaggedTrack {
        TaggedTrack(id: id, tags: tags, features: features)
    }

    private func makeTracks(forClass className: String, count: Int, idPrefix: String) -> [TaggedTrack] {
        (0..<count).map { i in
            makeTrack(id: "\(idPrefix)_\(i)", tags: [className], features: [Float(i), Float(i + 1), Float(i + 2)])
        }
    }

    // MARK: - Basic Generation Tests

    func testGenerateTrainingDataForValidGroup() {
        // Create 25 tracks each for Walking and Rolling (above default min of 20)
        var tracks = makeTracks(forClass: "WalkingBass", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 25, idPrefix: "rolling")

        let result = generator.generateTrainingData(for: "BassType", from: tracks)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.groupName, "BassType")
        XCTAssertEqual(result?.classes.sorted(), ["Rolling", "Walking"])
        XCTAssertEqual(result?.samples.count, 50)
    }

    func testGenerateTrainingDataReturnsNilForUnknownGroup() {
        let tracks = makeTracks(forClass: "Walking", count: 30, idPrefix: "walk")

        let result = generator.generateTrainingData(for: "UnknownGroup", from: tracks)

        XCTAssertNil(result)
    }

    func testGenerateTrainingDataReturnsNilWhenInsufficientSamples() {
        // Only 10 samples per class (below default min of 20)
        var tracks = makeTracks(forClass: "Walking", count: 10, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 10, idPrefix: "rolling")

        let result = generator.generateTrainingData(for: "BassType", from: tracks)

        XCTAssertNil(result)
    }

    func testGenerateTrainingDataReturnsNilWhenOnlyOneValidClass() {
        // 25 Walking samples but only 10 Rolling (one class insufficient)
        var tracks = makeTracks(forClass: "Walking", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 10, idPrefix: "rolling")

        let result = generator.generateTrainingData(for: "BassType", from: tracks)

        XCTAssertNil(result)
    }

    func testGenerateTrainingDataIgnoresTracksWithoutFeatures() {
        var tracks = makeTracks(forClass: "Walking", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 25, idPrefix: "rolling")
        // Add tracks without features - should be ignored
        tracks.append(makeTrack(id: "no_features", tags: ["Walking"], features: nil))

        let result = generator.generateTrainingData(for: "BassType", from: tracks)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.samples.count, 50)  // The nil-features track is not counted
    }

    func testGenerateTrainingDataIgnoresUnrelatedTags() {
        var tracks = makeTracks(forClass: "Walking", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 25, idPrefix: "rolling")
        // Add tracks with tags not in the BassType group
        tracks += makeTracks(forClass: "High", count: 25, idPrefix: "high_energy")  // Energy group, not BassType

        let result = generator.generateTrainingData(for: "BassType", from: tracks)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.samples.count, 50)  // Only BassType tracks
        XCTAssertFalse(result!.classes.contains("High"))
    }

    // MARK: - Custom Minimum Samples Tests

    func testGenerateTrainingDataWithCustomMinSamples() {
        // 15 samples per class - fails with default 20, passes with 10
        var tracks = makeTracks(forClass: "Walking", count: 15, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 15, idPrefix: "rolling")

        let defaultResult = generator.generateTrainingData(for: "BassType", from: tracks)
        XCTAssertNil(defaultResult)

        let customResult = generator.generateTrainingData(for: "BassType", from: tracks, minSamplesPerClass: 10)
        XCTAssertNotNil(customResult)
        XCTAssertEqual(customResult?.samples.count, 30)
    }

    // MARK: - ClassCounts Tests

    func testClassCountsComputedProperty() {
        var tracks = makeTracks(forClass: "Walking", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 30, idPrefix: "rolling")

        let result = generator.generateTrainingData(for: "BassType", from: tracks)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.classCounts["Walking"], 25)
        XCTAssertEqual(result?.classCounts["Rolling"], 30)
    }

    // MARK: - Viable Groups Tests

    func testViableGroupsReturnsGroupsWithSufficientData() {
        // BassType: 25 Walking, 25 Rolling (viable)
        var tracks = makeTracks(forClass: "Walking", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 25, idPrefix: "rolling")
        // Energy: 25 Low, 25 High (viable)
        tracks += makeTracks(forClass: "Low", count: 25, idPrefix: "low")
        tracks += makeTracks(forClass: "High", count: 25, idPrefix: "high")

        let viable = generator.viableGroups(from: tracks)

        XCTAssertEqual(viable, ["BassType", "Energy"])
    }

    func testViableGroupsExcludesInsufficientGroups() {
        // BassType: viable
        var tracks = makeTracks(forClass: "Walking", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 25, idPrefix: "rolling")
        // Energy: not viable (insufficient samples)
        tracks += makeTracks(forClass: "Low", count: 5, idPrefix: "low")
        tracks += makeTracks(forClass: "High", count: 5, idPrefix: "high")

        let viable = generator.viableGroups(from: tracks)

        XCTAssertEqual(viable, ["BassType"])
    }

    func testViableGroupsWithCustomMinSamples() {
        var tracks = makeTracks(forClass: "Walking", count: 15, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 15, idPrefix: "rolling")

        let defaultViable = generator.viableGroups(from: tracks)
        XCTAssertTrue(defaultViable.isEmpty)

        let customViable = generator.viableGroups(from: tracks, minSamplesPerClass: 10)
        XCTAssertEqual(customViable, ["BassType"])
    }

    func testViableGroupsWithCustomMinClasses() {
        // BassType: 3 valid classes (Walking, Rolling, Punchy)
        var tracks = makeTracks(forClass: "Walking", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "Rolling", count: 25, idPrefix: "rolling")
        tracks += makeTracks(forClass: "Punchy", count: 25, idPrefix: "punchy")
        // Energy: only 2 valid classes (Low, High)
        tracks += makeTracks(forClass: "Low", count: 25, idPrefix: "low")
        tracks += makeTracks(forClass: "High", count: 25, idPrefix: "high")

        // With minClasses=3, only BassType qualifies
        let viable3 = generator.viableGroups(from: tracks, minClasses: 3)
        XCTAssertEqual(viable3, ["BassType"])

        // With minClasses=2, both qualify
        let viable2 = generator.viableGroups(from: tracks, minClasses: 2)
        XCTAssertEqual(viable2, ["BassType", "Energy"])
    }

    // MARK: - Partial Tag Matching Tests

    func testPartialTagMatchingNormalizesToCanonicalClass() {
        // "WalkingBass" should normalize to "Walking"
        var tracks = makeTracks(forClass: "WalkingBass", count: 25, idPrefix: "walking")
        tracks += makeTracks(forClass: "RollingBass", count: 25, idPrefix: "rolling")

        let result = generator.generateTrainingData(for: "BassType", from: tracks)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.classes.sorted(), ["Rolling", "Walking"])

        // Verify all samples have canonical class names, not the original tag names
        for sample in result!.samples {
            XCTAssertTrue(["Walking", "Rolling"].contains(sample.className), "Sample class should be canonical: \(sample.className)")
        }
    }

    // MARK: - Empty Input Tests

    func testGenerateTrainingDataWithEmptyTracks() {
        let result = generator.generateTrainingData(for: "BassType", from: [])

        XCTAssertNil(result)
    }

    func testViableGroupsWithEmptyTracks() {
        let viable = generator.viableGroups(from: [])

        XCTAssertTrue(viable.isEmpty)
    }

    // MARK: - Determinism Tests

    func testDeterministicLabelAssignmentWithMultipleTags() {
        // Track with multiple tags in the same group
        // Should always pick the same one (alphabetically first normalized class)
        let tracks = [
            makeTrack(id: "multi1", tags: ["Walking", "Rolling"], features: [1.0, 2.0, 3.0]),
            makeTrack(id: "multi2", tags: ["Rolling", "Walking"], features: [4.0, 5.0, 6.0]),
        ]

        // Add enough samples to meet threshold
        var allTracks = tracks
        allTracks += makeTracks(forClass: "Walking", count: 25, idPrefix: "walk")
        allTracks += makeTracks(forClass: "Rolling", count: 25, idPrefix: "roll")

        // Run multiple times - should always produce same result
        var results: [String] = []
        for _ in 0..<10 {
            let result = generator.generateTrainingData(for: "BassType", from: allTracks)
            let multiTagSamples = result?.samples.filter { $0.trackId.starts(with: "multi") }
            let classes = multiTagSamples?.map { $0.className }.sorted()
            results.append(classes?.joined(separator: ",") ?? "")
        }

        // All runs should produce identical results
        XCTAssertEqual(Set(results).count, 1, "Label assignment should be deterministic")

        // Both multi-tag tracks should get the same class
        let result = generator.generateTrainingData(for: "BassType", from: allTracks)
        let multi1 = result?.samples.first { $0.trackId == "multi1" }
        let multi2 = result?.samples.first { $0.trackId == "multi2" }
        XCTAssertEqual(multi1?.className, multi2?.className)
    }
}
