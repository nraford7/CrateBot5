import XCTest
@testable import CrateBotCore

final class BinaryTrainingDataGeneratorTests: XCTestCase {
    func testMinimumPositiveExamples() {
        XCTAssertEqual(BinaryTrainingDataGenerator.minPositiveExamples, 50)
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
}
