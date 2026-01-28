import XCTest
@testable import CrateBotCore

final class ExperimentRunnerTests: XCTestCase {

    func testExperimentConfigurationCreation() {
        let config = ExperimentConfiguration(
            name: "Test Experiment",
            sampleSize: .small,
            extractors: ["spectral"],
            folds: 5,
            tags: ["House", "Techno"]
        )

        XCTAssertEqual(config.name, "Test Experiment")
        XCTAssertEqual(config.sampleSize, .small)
        XCTAssertEqual(config.extractors, ["spectral"])
        XCTAssertEqual(config.folds, 5)
    }

    func testExperimentResultStructure() {
        let tagResult = TagExperimentResult(
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
            sampleCount: 101
        )

        XCTAssertEqual(tagResult.tag, "House")
        XCTAssertEqual(tagResult.metrics.accuracy, 0.85)
        XCTAssertEqual(tagResult.optimalThreshold, 0.45)
    }

    func testExperimentResultSummary() {
        let results = [
            TagExperimentResult(
                tag: "House",
                metrics: ValidationMetrics(accuracy: 0.8, precision: 0.8, recall: 0.8, f1Score: 0.8,
                    truePositives: 40, falsePositives: 10, trueNegatives: 40, falseNegatives: 10),
                optimalThreshold: 0.5,
                sampleCount: 100
            ),
            TagExperimentResult(
                tag: "Techno",
                metrics: ValidationMetrics(accuracy: 0.9, precision: 0.9, recall: 0.9, f1Score: 0.9,
                    truePositives: 45, falsePositives: 5, trueNegatives: 45, falseNegatives: 5),
                optimalThreshold: 0.5,
                sampleCount: 100
            )
        ]

        let experiment = ExperimentResult(
            configuration: ExperimentConfiguration(
                name: "Test",
                sampleSize: .small,
                extractors: ["spectral"],
                folds: 5,
                tags: ["House", "Techno"]
            ),
            tagResults: results,
            duration: 60.0,
            tracksUsed: 50
        )

        XCTAssertEqual(experiment.averageAccuracy, 0.85, accuracy: 0.01)
        XCTAssertEqual(experiment.averageF1, 0.85, accuracy: 0.01)
    }

    func testTagViability() {
        // Viable: 50+ positive samples AND F1 >= 0.6
        let viableTag = TagExperimentResult(
            tag: "House",
            metrics: ValidationMetrics(accuracy: 0.8, precision: 0.75, recall: 0.85, f1Score: 0.79,
                truePositives: 42, falsePositives: 14, trueNegatives: 38, falseNegatives: 8),
            optimalThreshold: 0.5,
            sampleCount: 102,
            positiveCount: 50,
            negativeCount: 52
        )

        let nonViableLowSamples = TagExperimentResult(
            tag: "Disco",
            metrics: ValidationMetrics(accuracy: 0.8, precision: 0.8, recall: 0.8, f1Score: 0.8,
                truePositives: 16, falsePositives: 4, trueNegatives: 16, falseNegatives: 4),
            optimalThreshold: 0.5,
            sampleCount: 40,
            positiveCount: 20,
            negativeCount: 20
        )

        let nonViableLowF1 = TagExperimentResult(
            tag: "Other",
            metrics: ValidationMetrics(accuracy: 0.55, precision: 0.5, recall: 0.6, f1Score: 0.54,
                truePositives: 30, falsePositives: 30, trueNegatives: 25, falseNegatives: 20),
            optimalThreshold: 0.5,
            sampleCount: 105,
            positiveCount: 50,
            negativeCount: 55
        )

        XCTAssertTrue(viableTag.isViable)
        XCTAssertFalse(nonViableLowSamples.isViable)
        XCTAssertFalse(nonViableLowF1.isViable)
    }
}
