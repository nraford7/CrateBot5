import XCTest
import AVFoundation
@testable import CrateBotCore

final class MelSpectrogramGeneratorTests: XCTestCase {

    func testOutputShape() async throws {
        let generator = MelSpectrogramGenerator()

        // Create 1 second of 16kHz audio (sine wave)
        let sampleRate: Double = 16000
        let duration: Double = 1.0
        let frequency: Double = 440.0
        let samples = (0..<Int(sampleRate * duration)).map { i in
            Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
        }

        let buffer = try createBuffer(samples: samples, sampleRate: sampleRate)
        let melSpec = try generator.generate(from: buffer)

        // EffNet expects [128, 96] - 128 mel bands, 96 time frames
        XCTAssertEqual(melSpec.count, 128, "Should have 128 mel bands")
        XCTAssertEqual(melSpec[0].count, 96, "Should have 96 time frames")
    }

    func testValuesNormalized() async throws {
        let generator = MelSpectrogramGenerator()
        let samples = [Float](repeating: 0.5, count: 16000)
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
