import XCTest
@testable import CrateBotCore

final class BinaryTrainingDataGeneratorTests: XCTestCase {
    func testDefaultMinimumPositiveExamples() {
        let generator = BinaryTrainingDataGenerator()
        XCTAssertEqual(generator.minPositiveExamples, 50)
        XCTAssertEqual(generator.maxNegativeRatio, 3.0)
    }

    func testReturnsNilForInsufficientData() {
        let generator = BinaryTrainingDataGenerator()

        // Create 10 tracks with "funky" tag (below minimum)
        let tracks = (0..<100).map { i in
            TaggedTrack(id: "\(i)", tags: i < 10 ? ["funky"] : [])
        }

        let result = generator.generateTrainingData(for: "funky", from: tracks)
        XCTAssertNil(result)
    }

    func testGeneratesBalancedData() {
        let generator = BinaryTrainingDataGenerator()

        // Create 60 positive and 200 negative tracks
        let tracks = (0..<260).map { i in
            TaggedTrack(id: "\(i)", tags: i < 60 ? ["funky"] : [])
        }

        let result = generator.generateTrainingData(for: "funky", from: tracks)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.positive.count, 60)
        // Max negative ratio is 3:1, so max 180 negatives
        XCTAssertLessThanOrEqual(result?.negative.count ?? 0, 180)
    }

    func testGeneratorUsesCustomMinSamples() {
        let generator = BinaryTrainingDataGenerator(minPositiveExamples: 10, maxNegativeRatio: 2.0)

        var tracks: [TaggedTrack] = []
        for i in 0..<15 {
            tracks.append(TaggedTrack(id: "pos\(i)", tags: ["TestTag"], features: [Float(i)]))
        }
        for i in 0..<50 {
            tracks.append(TaggedTrack(id: "neg\(i)", tags: ["OtherTag"], features: [Float(i)]))
        }

        let result = generator.generateTrainingData(for: "TestTag", from: tracks)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.positive.count, 15)
        XCTAssertEqual(result?.negative.count, 30)  // 15 * 2.0 ratio
    }

    func testGeneratorWithDefaultMinSamplesRejectsSmallDataset() {
        let generator = BinaryTrainingDataGenerator()

        var tracks: [TaggedTrack] = []
        for i in 0..<15 {
            tracks.append(TaggedTrack(id: "pos\(i)", tags: ["TestTag"], features: [Float(i)]))
        }
        for i in 0..<50 {
            tracks.append(TaggedTrack(id: "neg\(i)", tags: ["OtherTag"], features: [Float(i)]))
        }

        let result = generator.generateTrainingData(for: "TestTag", from: tracks)

        XCTAssertNil(result)  // 15 < 50 default threshold
    }
}
