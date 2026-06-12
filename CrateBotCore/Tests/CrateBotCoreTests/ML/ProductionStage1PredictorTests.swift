import XCTest
@testable import CrateBotCore

/// The production Stage1Predictor must emit exactly what inference feeds
/// Stage 2: CALIBRATED, PRE-BOOST confidences — mirroring TaggingEngine's
/// pass-1 (predictWithConfidence → confidenceCalibrator.calibrate), with no
/// co-occurrence boosting and no thresholding.
final class ProductionStage1PredictorTests: XCTestCase {

    /// Trains a tiny real binary classifier and returns its model URL.
    private func trainTinyBinaryModel(tag: String, in directory: URL) async throws -> URL {
        var tracks: [TaggedTrack] = []
        for i in 0..<15 {
            tracks.append(TaggedTrack(
                id: "pos_\(i)", tags: [tag],
                features: (0..<20).map { _ in Float.random(in: 0.7...1.0) }
            ))
            tracks.append(TaggedTrack(
                id: "neg_\(i)", tags: [],
                features: (0..<20).map { _ in Float.random(in: 0.0...0.3) }
            ))
        }
        let trainer = ModelTrainer()
        let results = try await trainer.trainModels(
            from: tracks,
            tags: [tag],
            outputDirectory: directory,
            config: TrainingConfig(minSamplesPerTag: 10, mixupEnabled: false)
        )
        return try XCTUnwrap(results.first?.modelURL)
    }

    func testEmitsCalibratedPreBoostConfidences() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let modelURL = try await trainTinyBinaryModel(tag: "TestTag", in: tempDir)

        let classifier = try TagClassifier(tagName: "TestTag", modelURL: modelURL, threshold: 0.5)
        // Non-trivial temperature so calibrated != raw — proves calibration ran
        let calibrator = ConfidenceCalibrator(temperature: 2.0, smoothingFactor: 0.1)
        let predictor = ProductionStage1Predictor(
            classifiers: [classifier],
            groupClassifiers: [:],
            calibrator: calibrator
        )

        let features = [Float](repeating: 0.85, count: 20)
        let (binary, groups) = try await predictor.confidences(features: features)

        let (_, raw) = try classifier.predictWithConfidence(features: features)
        XCTAssertEqual(binary["TestTag"], calibrator.calibrate(raw),
            "Predictor must emit calibrate(rawConfidence), matching TaggingEngine pass-1")
        XCTAssertNotEqual(binary["TestTag"], raw,
            "Calibration with temperature 2.0 must actually transform the raw confidence")
        XCTAssertTrue(groups.isEmpty)
    }

    func testLoadExcludesJudgmentAndMultiClassModels() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let modelURL = try await trainTinyBinaryModel(tag: "TestTag", in: tempDir)

        // Pose copies of the same model as Stage 2 and multi-class files —
        // the loader must not treat them as Stage 1 binary classifiers.
        let fm = FileManager.default
        try fm.copyItem(at: modelURL, to: tempDir.appendingPathComponent("Peak_judgment.mlmodel"))
        try fm.copyItem(at: modelURL, to: tempDir.appendingPathComponent("BassType_multiclass.mlmodel"))

        let predictor = try ProductionStage1Predictor.load(from: tempDir, metadata: nil)

        XCTAssertEqual(predictor.binaryTagNames, ["TestTag"])
    }
}
