import XCTest
@testable import CrateBotCore

final class EssentiaClassifierTests: XCTestCase {

    func testMoodThemeClassification() async throws {
        let classifier = try EssentiaClassifier()

        // Create dummy embeddings (1280 dims)
        let embeddings = [Float](repeating: 0.1, count: 1280)

        let predictions = try await classifier.predictMoodTheme(embeddings: embeddings)

        XCTAssertEqual(predictions.count, 56, "Should return 56 mood/theme predictions")

        // All values should be probabilities [0, 1]
        for (tag, prob) in predictions {
            XCTAssertGreaterThanOrEqual(prob, 0, "\(tag) probability should be >= 0")
            XCTAssertLessThanOrEqual(prob, 1, "\(tag) probability should be <= 1")
        }
    }

    func testInstrumentClassification() async throws {
        let classifier = try EssentiaClassifier()

        let embeddings = [Float](repeating: 0.1, count: 1280)

        let predictions = try await classifier.predictInstruments(embeddings: embeddings)

        XCTAssertEqual(predictions.count, 40, "Should return 40 instrument predictions")
    }

    func testGenreLabeling() throws {
        let classifier = try EssentiaClassifier()

        // Create dummy activations (400 dims)
        let activations = [Float](repeating: 0.0, count: 400)

        let predictions = classifier.labelGenres(activations: activations)

        XCTAssertEqual(predictions.count, 400, "Should return 400 genre predictions")
    }

    func testTopPredictions() throws {
        let classifier = try EssentiaClassifier()

        let predictions: [String: Float] = [
            "happy": 0.9,
            "sad": 0.7,
            "energetic": 0.5,
            "calm": 0.05,  // Below threshold
            "dark": 0.3
        ]

        let top = classifier.topPredictions(predictions, count: 3, threshold: 0.1)

        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top[0].tag, "happy")
        XCTAssertEqual(top[1].tag, "sad")
        XCTAssertEqual(top[2].tag, "energetic")
    }

    func testLabelsLoaded() {
        XCTAssertEqual(EssentiaLabels.moodTheme.count, 56, "Should have 56 mood labels")
        XCTAssertEqual(EssentiaLabels.instruments.count, 40, "Should have 40 instrument labels")
        XCTAssertEqual(EssentiaLabels.genres.count, 400, "Should have 400 genre labels")

        // Check some known labels exist
        XCTAssertTrue(EssentiaLabels.moodTheme.contains("happy"))
        XCTAssertTrue(EssentiaLabels.instruments.contains("piano"))
    }
}
