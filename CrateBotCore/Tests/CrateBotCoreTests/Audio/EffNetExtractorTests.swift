import XCTest
import AVFoundation
@testable import CrateBotCore

final class EffNetExtractorTests: XCTestCase {

    func testFeatureCount() throws {
        let extractor = try EffNetExtractor()
        XCTAssertEqual(extractor.featureCount, 1280, "EffNet should produce 1280-dim embeddings")
    }

    func testExtractorMetadata() throws {
        let extractor = try EffNetExtractor()
        XCTAssertEqual(extractor.id, "effnet")
        XCTAssertEqual(extractor.version, "v1")
    }

    func testExtraction() async throws {
        let extractor = try EffNetExtractor()

        // Create test audio buffer (3 seconds of noise at 16kHz)
        // Need at least 33,024 samples for 128 time frames
        let sampleRate: Double = 16000
        let samples = (0..<48000).map { _ in Float.random(in: -1...1) }
        let buffer = try createBuffer(samples: samples, sampleRate: sampleRate)

        let features = try await extractor.extract(from: buffer)

        XCTAssertEqual(features.count, 1280, "Should produce 1280 features")

        // Features should be non-zero for real audio
        let nonZeroCount = features.filter { abs($0) > 0.001 }.count
        XCTAssertGreaterThan(nonZeroCount, 100, "Most features should be non-zero")
    }

    func testExtractionWithGenres() async throws {
        let extractor = try EffNetExtractor()

        // Create test audio (3 seconds at 16kHz)
        // Need at least 33,024 samples for 128 time frames
        let sampleRate: Double = 16000
        let samples = (0..<48000).map { i in
            Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate))
        }
        let buffer = try createBuffer(samples: samples, sampleRate: sampleRate)

        let result = try await extractor.extractWithGenres(from: buffer)

        XCTAssertEqual(result.embeddings.count, 1280, "Should produce 1280 embeddings")
        XCTAssertEqual(result.genreActivations.count, 400, "Should produce 400 genre activations")
    }

    private func createBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }
}
