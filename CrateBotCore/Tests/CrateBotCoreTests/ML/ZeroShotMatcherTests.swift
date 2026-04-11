import XCTest
@testable import CrateBotCore

final class ZeroShotMatcherTests: XCTestCase {

    // MARK: - Cosine Similarity

    func testCosineSimilarityIdentical() {
        let v: [Float] = [1, 2, 3, 4, 5]
        let sim = ZeroShotMatcher.cosineSimilarity(v, v)
        XCTAssertEqual(sim, 1.0, accuracy: 1e-5)
    }

    func testCosineSimilarityOrthogonal() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        let sim = ZeroShotMatcher.cosineSimilarity(a, b)
        XCTAssertEqual(sim, 0.0, accuracy: 1e-5)
    }

    func testCosineSimilarityOpposite() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [-1, -2, -3]
        let sim = ZeroShotMatcher.cosineSimilarity(a, b)
        XCTAssertEqual(sim, -1.0, accuracy: 1e-5)
    }

    // MARK: - Match

    func testMatchReturnsTagsAboveThreshold() {
        // Construct embeddings where "rock" is very similar, "jazz" is moderate, "noise" is below threshold
        let audio: [Float] = [1, 0, 0]
        let embeddings: [String: [Float]] = [
            "rock":  [1, 0, 0],      // similarity 1.0
            "jazz":  [0.8, 0.6, 0],  // similarity 0.8
            "noise": [0, 0, 1],      // similarity 0.0
        ]

        let matcher = ZeroShotMatcher(tagEmbeddings: embeddings)
        let results = matcher.match(audioEmbedding: audio, threshold: 0.5)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].tag, "rock")
        XCTAssertEqual(results[0].similarity, 1.0, accuracy: 1e-5)
        XCTAssertEqual(results[1].tag, "jazz")
        XCTAssertTrue(results[1].similarity > 0.5)
    }

    func testMatchExcludesTrainedTags() {
        let audio: [Float] = [1, 0, 0]
        let embeddings: [String: [Float]] = [
            "rock":    [1, 0, 0],
            "jazz":    [0.9, 0.4, 0],
            "ambient": [0.8, 0.6, 0],
        ]

        let matcher = ZeroShotMatcher(tagEmbeddings: embeddings)
        let results = matcher.match(
            audioEmbedding: audio,
            threshold: 0.0,
            excludingTags: ["rock", "jazz"]
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].tag, "ambient")
    }

    func testLoadFromBundleLoadsEmbeddings() {
        // clap_tag_embeddings.json is bundled as a resource
        let matcher = ZeroShotMatcher.loadFromBundle()
        XCTAssertNotNil(matcher)
    }
}
