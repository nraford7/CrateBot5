import XCTest
import AVFoundation
@testable import CrateBotCore

final class MelSpectrogramGeneratorTests: XCTestCase {

    func testOutputShape() async throws {
        let generator = MelSpectrogramGenerator()

        // Create 3 seconds of 16kHz audio (sine wave) - need ~2.1s for 128 frames
        // Required: (128 - 1) * 256 + 512 = 33,024 samples = 2.064s
        let sampleRate: Double = 16000
        let duration: Double = 3.0
        let frequency: Double = 440.0
        let samples = (0..<Int(sampleRate * duration)).map { i in
            Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
        }

        let buffer = try createBuffer(samples: samples, sampleRate: sampleRate)
        let melSpec = try generator.generate(from: buffer)

        // EffNet expects input [batch, 128 time_frames, 96 mel_bands]
        // Generator produces [96 mel_bands][128 time_frames]
        XCTAssertEqual(melSpec.count, 96, "Should have 96 mel bands")
        XCTAssertEqual(melSpec[0].count, 128, "Should have 128 time frames")
    }

    func testValuesNormalized() async throws {
        let generator = MelSpectrogramGenerator()
        // Need at least 33,024 samples (2.1s at 16kHz) for 128 time frames
        let samples = [Float](repeating: 0.5, count: 48000)  // 3 seconds
        let buffer = try createBuffer(samples: samples, sampleRate: 16000)

        let melSpec = try generator.generate(from: buffer)

        // Values should be in reasonable range (log-scaled mel energies)
        let flatValues = melSpec.flatMap { $0 }
        let maxVal = flatValues.max() ?? 0
        let minVal = flatValues.min() ?? 0

        XCTAssertLessThan(maxVal, 100, "Max value should be bounded")
        XCTAssertGreaterThan(minVal, -100, "Min value should be bounded")
    }

    private func createBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        return buffer
    }
}
