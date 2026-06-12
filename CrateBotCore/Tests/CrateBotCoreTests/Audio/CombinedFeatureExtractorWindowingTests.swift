import XCTest
import AVFoundation
@testable import CrateBotCore

/// Tests for multi-window extraction in CombinedFeatureExtractor:
/// window slicing at fractional start positions, short-track collapse,
/// per-block mean pooling, and output-dimension stability.
final class CombinedFeatureExtractorWindowingTests: XCTestCase {

    func testSliceWindowsProducesRequestedCount() throws {
        // 180s of 16kHz audio → 5 windows of 15s at the configured fractions
        let buffer = try makeSyntheticBuffer(seconds: 180, sampleRate: 16000)
        let windows = CombinedFeatureExtractor.sliceWindows(
            buffer: buffer, fractions: [0.1, 0.3, 0.5, 0.7, 0.9], duration: 15.0)
        XCTAssertEqual(windows.count, 5)
        XCTAssertEqual(windows[0].frameLength, AVAudioFrameCount(15.0 * 16000))
    }

    func testShortTrackCollapsesToFewerWindows() throws {
        // 20s track: windows overlap heavily → deduplicated to distinct starts, min 1
        let buffer = try makeSyntheticBuffer(seconds: 20, sampleRate: 16000)
        let windows = CombinedFeatureExtractor.sliceWindows(
            buffer: buffer, fractions: [0.1, 0.3, 0.5, 0.7, 0.9], duration: 15.0)
        XCTAssertGreaterThanOrEqual(windows.count, 1)
        XCTAssertLessThan(windows.count, 5)
    }

    func testMeanPoolAverages() {
        let pooled = CombinedFeatureExtractor.meanPool([[1, 2], [3, 4]])
        XCTAssertEqual(pooled, [2, 3])
    }

    func testWindowedExtractionOutputDimensionUnchanged() async throws {
        // Skip if model not available in test environment
        let extractor: CombinedFeatureExtractor
        do {
            extractor = try CombinedFeatureExtractor(config: .effnetPlusGenres)
        } catch {
            throw XCTSkip("CombinedFeatureExtractor requires EffNet model: \(error)")
        }

        let buffer = try makeSyntheticBuffer(seconds: 120, sampleRate: 16000)
        let vector = try await extractor.extractWindowed(
            from: buffer, config: FeatureExtractionConfig.default)
        XCTAssertEqual(vector.count, 1680)   // same shape as single-shot
    }

    // MARK: - Helpers

    private func makeSyntheticBuffer(seconds: Double, sampleRate: Double) throws -> AVAudioPCMBuffer {
        let sampleCount = Int(seconds * sampleRate)
        let samples = (0..<sampleCount).map { i in
            Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate))
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw CombinedFeatureError.bufferCreationFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }
}
