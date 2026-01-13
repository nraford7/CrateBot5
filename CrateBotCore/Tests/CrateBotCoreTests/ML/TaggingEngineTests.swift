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

        // Create synthetic audio buffer (1 second of noise at 16kHz)
        let sampleRate: Double = 16000
        let samples = (0..<16000).map { _ in Float.random(in: -0.5...0.5) }
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
}
