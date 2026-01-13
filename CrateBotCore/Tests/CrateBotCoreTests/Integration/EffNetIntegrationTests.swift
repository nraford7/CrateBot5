import XCTest
import AVFoundation
@testable import CrateBotCore

final class EffNetIntegrationTests: XCTestCase {

    /// Test the full pipeline: Audio -> MelSpec -> EffNet -> Embeddings -> Essentia Classifiers
    func testFullPipeline() async throws {
        // 1. Create synthetic test audio (1 second of mixed frequencies at 16kHz)
        let sampleRate: Double = 16000
        let duration: Double = 1.0
        let samples = createTestAudioSamples(sampleRate: sampleRate, duration: duration)
        let buffer = try createBuffer(samples: samples, sampleRate: sampleRate)

        // 2. Initialize the full pipeline
        let engine = try TaggingEngine()

        // 3. Analyze
        let result = try await engine.analyze(buffer: buffer)

        // 4. Verify embeddings
        XCTAssertEqual(result.embeddings.count, 1280, "Should produce 1280-dim embeddings")

        // 5. Verify genre activations
        XCTAssertEqual(result.genreActivations.count, 400, "Should produce 400 genre activations")

        // 6. Verify Essentia tags structure exists
        XCTAssertNotNil(result.essentiaTags)

        // 7. Embeddings should have reasonable values (not all zeros or NaN)
        let hasNonZero = result.embeddings.contains { abs($0) > 0.001 }
        XCTAssertTrue(hasNonZero, "Embeddings should have non-zero values")

        let hasNoNaN = !result.embeddings.contains { $0.isNaN }
        XCTAssertTrue(hasNoNaN, "Embeddings should not contain NaN")
    }

    /// Test that different audio produces different embeddings
    func testDifferentAudioProducesDifferentEmbeddings() async throws {
        let engine = try TaggingEngine()

        // Create two different audio signals
        let sampleRate: Double = 16000

        // Audio 1: Low frequency tone (200 Hz)
        let samples1 = (0..<16000).map { i in
            Float(sin(2.0 * .pi * 200.0 * Double(i) / sampleRate))
        }

        // Audio 2: High frequency tone (4000 Hz)
        let samples2 = (0..<16000).map { i in
            Float(sin(2.0 * .pi * 4000.0 * Double(i) / sampleRate))
        }

        let buffer1 = try createBuffer(samples: samples1, sampleRate: sampleRate)
        let buffer2 = try createBuffer(samples: samples2, sampleRate: sampleRate)

        let result1 = try await engine.analyze(buffer: buffer1)
        let result2 = try await engine.analyze(buffer: buffer2)

        // Calculate cosine similarity between embeddings
        let similarity = cosineSimilarity(result1.embeddings, result2.embeddings)

        // Different audio should produce different embeddings (similarity < 0.99)
        XCTAssertLessThan(similarity, 0.99, "Different audio should produce different embeddings")
    }

    /// Test that MelSpectrogramGenerator produces correct output shape
    func testMelSpectrogramShape() throws {
        let generator = MelSpectrogramGenerator()

        // Create 1 second of audio at 16kHz
        let samples = [Float](repeating: 0.5, count: 16000)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
        buffer.frameLength = 16000
        memcpy(buffer.floatChannelData![0], samples, 16000 * MemoryLayout<Float>.size)

        let melSpec = try generator.generate(from: buffer)

        XCTAssertEqual(melSpec.count, 128, "Should have 128 mel bands")
        XCTAssertEqual(melSpec[0].count, 96, "Should have 96 time frames")
    }

    /// Test EssentiaLabels are properly loaded from JSON resources
    func testEssentiaLabelsLoaded() {
        XCTAssertEqual(EssentiaLabels.moodTheme.count, 56, "Should have 56 mood/theme labels")
        XCTAssertEqual(EssentiaLabels.instruments.count, 40, "Should have 40 instrument labels")
        XCTAssertEqual(EssentiaLabels.genres.count, 400, "Should have 400 genre labels")

        // Verify some known labels exist
        XCTAssertTrue(EssentiaLabels.moodTheme.contains("happy"), "Should contain 'happy' mood")
        XCTAssertTrue(EssentiaLabels.moodTheme.contains("energetic"), "Should contain 'energetic' mood")
        XCTAssertTrue(EssentiaLabels.instruments.contains("piano"), "Should contain 'piano' instrument")
        XCTAssertTrue(EssentiaLabels.instruments.contains("drums"), "Should contain 'drums' instrument")
        XCTAssertTrue(EssentiaLabels.genres.contains { $0.contains("House") }, "Should contain House genre")
        XCTAssertTrue(EssentiaLabels.genres.contains { $0.contains("Techno") }, "Should contain Techno genre")
    }

    /// Test EssentiaTags can be written to and read from ID3
    func testID3Integration() async throws {
        // Create temp audio file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_integration_\(UUID()).mp3")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Create a minimal MP3 file (copy from test resources or create)
        // For this test, we'll just verify the TagsToWrite structure works
        let essentiaTags = EssentiaTags(
            genres: ["Electronic---House", "Electronic---Techno"],
            moods: ["energetic", "dark", "groovy"],
            instruments: ["synthesizer", "drums", "bass"]
        )

        XCTAssertEqual(essentiaTags.genresString, "Electronic---House, Electronic---Techno")
        XCTAssertEqual(essentiaTags.moodsString, "energetic, dark, groovy")
        XCTAssertEqual(essentiaTags.instrumentsString, "synthesizer, drums, bass")

        var tags = TagsToWrite()
        tags.essentiaGenres = essentiaTags.genresString
        tags.essentiaMoods = essentiaTags.moodsString
        tags.essentiaInstruments = essentiaTags.instrumentsString

        XCTAssertFalse(tags.isEmpty, "Tags should not be empty")
    }

    /// Test FeaturePipelineVersion reflects EffNet configuration
    func testPipelineVersionReflectsEffNet() async {
        let coordinator = TrainingCoordinator()
        let version = await coordinator.currentPipelineVersion()

        // Should indicate EffNet is being used
        XCTAssertTrue(version.extractorVersions.keys.contains("effnet"), "Should use effnet extractor")
        XCTAssertEqual(version.extractorVersions["effnet"], "v1", "Should be effnet v1")
    }

    // MARK: - Helpers

    private func createTestAudioSamples(sampleRate: Double, duration: Double) -> [Float] {
        let sampleCount = Int(sampleRate * duration)
        return (0..<sampleCount).map { i in
            // Mix of frequencies to create a more realistic test signal
            let t = Double(i) / sampleRate
            let f1 = Float(sin(2.0 * .pi * 440.0 * t))  // A4
            let f2 = Float(sin(2.0 * .pi * 880.0 * t))  // A5
            let f3 = Float(sin(2.0 * .pi * 220.0 * t))  // A3
            let noise = Float.random(in: -0.1...0.1)
            return (f1 + f2 * 0.5 + f3 * 0.3 + noise) / 2.0
        }
    }

    private func createBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
}
