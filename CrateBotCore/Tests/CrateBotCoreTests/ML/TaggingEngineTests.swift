import XCTest
import AVFoundation
@testable import CrateBotCore

final class TaggingEngineTests: XCTestCase {

    func testEngineInitialization() throws {
        let engine = try TaggingEngine()
        // Should initialize without error
        XCTAssertNotNil(engine)
    }

    func testAnalyzeWithSyntheticAudio() async throws {
        let engine = try TaggingEngine()

        // Create synthetic audio buffer (2.5 seconds of noise at 16kHz)
        // MelSpectrogramGenerator requires at least 33,024 samples
        let sampleRate: Double = 16000
        let samples = (0..<40000).map { _ in Float.random(in: -0.5...0.5) }
        let buffer = try createBuffer(samples: samples, sampleRate: sampleRate)

        let result = try await engine.analyze(buffer: buffer)

        // Verify embeddings
        XCTAssertEqual(result.embeddings.count, 1280, "Should have 1280-dim embeddings")
        XCTAssertEqual(result.genreActivations.count, 400, "Should have 400 genre activations")

        // Verify Essentia tags exist (may be empty if below threshold)
        XCTAssertNotNil(result.essentiaTags)

        // User predictions should be nil (no model loaded)
        XCTAssertNil(result.userPredictions)
    }

    func testHasUserModel() async throws {
        let engine = try TaggingEngine()

        // Initially no user model
        let hasModel = await engine.hasUserModel
        XCTAssertFalse(hasModel)
    }

    func testTaggingResultStructure() {
        let essentiaTags = EssentiaTags(
            genres: ["Electronic---House", "Electronic---Techno"],
            moods: ["energetic", "dark"],
            instruments: ["synthesizer", "drums"]
        )

        let result = TaggingResult(
            userPredictions: nil,
            essentiaTags: essentiaTags,
            embeddings: [Float](repeating: 0, count: 1280),
            genreActivations: [Float](repeating: 0, count: 400)
        )

        XCTAssertNil(result.userPredictions)
        XCTAssertEqual(result.essentiaTags.genres.count, 2)
        XCTAssertEqual(result.essentiaTags.moods.count, 2)
        XCTAssertEqual(result.essentiaTags.instruments.count, 2)
    }

    private func createBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }

    // MARK: - UserTagPredictions structured descriptive tests

    func testUserTagPredictionsHasStructuredDescriptive() {
        // Create predictions with organized descriptive output
        let predictions = UserTagPredictions(
            genre: "House",
            timing: "Peak",
            mood: "Uplifting",
            bassType: "Walking",
            rhythm: ["Broken", "Driving"],
            style: ["Afro"],
            vibes: ["Funky", "Dark"],
            instruments: ["Congas", "Organ"],
            vocalType: "Chanting",
            acapella: false
        )

        XCTAssertEqual(predictions.bassType, "Walking")
        XCTAssertEqual(predictions.rhythm, ["Broken", "Driving"])
        XCTAssertEqual(predictions.vocalType, "Chanting")
        XCTAssertFalse(predictions.acapella ?? true)
    }

    func testUserTagPredictionsDescriptiveArrayBackwardsCompat() {
        // Old-style descriptive array should still work
        let predictions = UserTagPredictions(
            genre: "House",
            timing: nil,
            mood: nil,
            descriptive: ["Funky", "Walking", "Congas"]
        )

        // The computed descriptive property returns tags in subcategory order:
        // bassType -> rhythm -> style -> vibes -> instruments -> vocalType
        // So "Walking" (bassType) comes first, then "Funky" (vibes), then "Congas" (instruments)
        XCTAssertEqual(predictions.descriptive, ["Walking", "Funky", "Congas"])

        // Verify the structured fields were populated correctly
        XCTAssertEqual(predictions.bassType, "Walking")
        XCTAssertEqual(predictions.vibes, ["Funky"])
        XCTAssertEqual(predictions.instruments, ["Congas"])
    }

    // MARK: - Model loading with modelName parameter

    func testLoadModelWithModelName() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadata = ModelMetadata(
            name: "TestModel",
            version: "1.0",
            pipelineVersion: "1.0",
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Genre"],
            tags: ["Genre": ["House", "Techno"]],
            tagGroups: [],
            accuracy: 0.85,
            featureDimension: 1680
        )
        // Save metadata with model name (the new convention)
        let metadataURL = tempDir.appendingPathComponent("TestModel.json")
        try metadata.save(to: metadataURL)

        // Create a dummy .mlmodel directory (empty directory is enough for file listing)
        // Note: This won't be a valid model, but we can verify the metadata loading path
        let dummyModelDir = tempDir.appendingPathComponent("House.mlmodel")
        try FileManager.default.createDirectory(at: dummyModelDir, withIntermediateDirectories: true)

        let engine = try TaggingEngine()
        // loadModel will find the .mlmodel directory but fail to load it as a classifier
        // Still, we can verify the model name is returned correctly based on the parameter
        let (count, name) = try await engine.loadModel(from: tempDir, modelName: "TestModel")
        XCTAssertEqual(name, "TestModel", "Model name should match the provided modelName parameter")
        // No classifiers will actually load since the model file is empty
        XCTAssertEqual(count, 0)
    }
}
