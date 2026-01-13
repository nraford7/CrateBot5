import XCTest
@testable import CrateBotCore

final class ModelLabIntegrationTests: XCTestCase {

    func testEndToEndExperimentWithMockData() async throws {
        // Create mock tracks with features
        var tracks: [TaggedTrack] = []

        // Generate 100 mock tracks with random features
        for i in 0..<100 {
            let tags: Set<String>
            if i < 30 {
                tags = ["House"]
            } else if i < 55 {
                tags = ["Techno"]
            } else if i < 70 {
                tags = ["Disco"]
            } else {
                tags = ["Other"]
            }

            // Random 32-dimensional features
            let features = (0..<32).map { _ in Float.random(in: -1...1) }
            tracks.append(TaggedTrack(id: "\(i)", tags: tags, features: features))
        }

        // Test stratified sampling
        let sampler = StratifiedSampler(seed: 42)
        let sample = sampler.sample(from: tracks, size: .small, stratifyBy: \.primaryTag)

        XCTAssertEqual(sample.count, 50)

        // Test cross-validation folds
        let validator = CrossValidator(folds: 5, seed: 42)
        let folds = validator.createFolds(from: sample)

        XCTAssertEqual(folds.count, 5)
        for fold in folds {
            XCTAssertEqual(fold.train.count + fold.test.count, 50)
        }

        // Test binary data generation
        let generator = BinaryTrainingDataGenerator()
        let viableTags = generator.viableTags(from: sample)

        // With 50 samples and stratified sampling, individual tags may not have 50+ positives
        // This demonstrates the minimum sample requirement
        XCTAssertTrue(viableTags.isEmpty || viableTags.values.allSatisfy { $0 >= 50 })
    }

    func testValidationMetricsCalculation() {
        // Test precision/recall trade-off
        let highPrecision: [(predicted: Bool, actual: Bool)] = [
            (true, true), (true, true),  // 2 TP
            (false, true), (false, true), (false, true),  // 3 FN
            (false, false), (false, false), (false, false), (false, false), (false, false)  // 5 TN
        ]

        let metrics = ValidationMetrics.calculate(from: highPrecision)

        XCTAssertEqual(metrics.precision, 1.0)  // No false positives
        XCTAssertEqual(metrics.recall, 0.4, accuracy: 0.01)  // 2/(2+3)
        XCTAssertLessThan(metrics.f1Score, 0.7)  // Low due to poor recall
    }

    func testExperimentConfigurationSerialization() throws {
        let config = ExperimentConfiguration(
            name: "Test",
            sampleSize: .balanced,
            extractors: ["spectral", "panns"],
            folds: 5,
            tags: ["House", "Techno"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExperimentConfiguration.self, from: data)

        XCTAssertEqual(decoded.name, config.name)
        XCTAssertEqual(decoded.extractors, config.extractors)
        XCTAssertEqual(decoded.folds, config.folds)
    }

    func testExperimentResultSerialization() throws {
        let result = ExperimentResult(
            configuration: ExperimentConfiguration(
                name: "Test",
                sampleSize: .small,
                extractors: ["spectral"],
                folds: 5
            ),
            tagResults: [
                TagExperimentResult(
                    tag: "House",
                    metrics: ValidationMetrics(
                        accuracy: 0.85,
                        precision: 0.80,
                        recall: 0.90,
                        f1Score: 0.85,
                        truePositives: 45,
                        falsePositives: 11,
                        trueNegatives: 40,
                        falseNegatives: 5
                    ),
                    optimalThreshold: 0.45,
                    sampleCount: 101,
                    positiveCount: 50,
                    negativeCount: 51
                )
            ],
            duration: 60.0,
            tracksUsed: 100
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExperimentResult.self, from: data)

        XCTAssertEqual(decoded.configuration.name, result.configuration.name)
        XCTAssertEqual(decoded.tagResults.count, 1)
        XCTAssertEqual(decoded.tagResults[0].tag, "House")
        XCTAssertEqual(decoded.averageAccuracy, 0.85, accuracy: 0.01)
    }

    func testSampleSizeEstimatedTimes() {
        // Verify all sample sizes have estimated times
        for size in SampleSize.allCases {
            XCTAssertFalse(size.estimatedTime.isEmpty, "\(size) should have estimated time")
        }
    }

    func testViabilityThreshold() {
        // Viable: 50+ positive samples AND F1 >= 0.6
        let barelyViable = TagExperimentResult(
            tag: "Test",
            metrics: ValidationMetrics(
                accuracy: 0.7, precision: 0.65, recall: 0.65, f1Score: 0.6,
                truePositives: 32, falsePositives: 17, trueNegatives: 38, falseNegatives: 18
            ),
            optimalThreshold: 0.5,
            sampleCount: 105,
            positiveCount: 50,
            negativeCount: 55
        )

        let barelyNotViableF1 = TagExperimentResult(
            tag: "Test",
            metrics: ValidationMetrics(
                accuracy: 0.7, precision: 0.6, recall: 0.58, f1Score: 0.59,
                truePositives: 29, falsePositives: 19, trueNegatives: 41, falseNegatives: 21
            ),
            optimalThreshold: 0.5,
            sampleCount: 110,
            positiveCount: 50,
            negativeCount: 60
        )

        let barelyNotViableSamples = TagExperimentResult(
            tag: "Test",
            metrics: ValidationMetrics(
                accuracy: 0.8, precision: 0.8, recall: 0.8, f1Score: 0.8,
                truePositives: 39, falsePositives: 10, trueNegatives: 39, falseNegatives: 10
            ),
            optimalThreshold: 0.5,
            sampleCount: 98,
            positiveCount: 49,
            negativeCount: 49
        )

        XCTAssertTrue(barelyViable.isViable, "Should be viable with exactly 50 samples and F1=0.6")
        XCTAssertFalse(barelyNotViableF1.isViable, "Should not be viable with F1=0.59")
        XCTAssertFalse(barelyNotViableSamples.isViable, "Should not be viable with 49 samples")
    }
}
