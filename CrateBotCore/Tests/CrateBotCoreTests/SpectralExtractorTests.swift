import XCTest
import AVFoundation
@testable import CrateBotCore

final class SpectralExtractorTests: XCTestCase {
    var extractor: SpectralExtractor!

    override func setUp() {
        extractor = SpectralExtractor()
    }

    func testExtractorId() {
        XCTAssertEqual(extractor.id, "spectral")
    }

    func testFeatureCountIsPositive() {
        XCTAssertGreaterThan(extractor.featureCount, 0)
    }

    func testExtractFromSineWave() async throws {
        // Create a 1-second sine wave buffer at 22050 Hz
        let sampleRate: Double = 22050
        let duration: Double = 1.0
        let frequency: Float = 440.0  // A4 note

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * duration))
        else {
            XCTFail("Failed to create test buffer")
            return
        }

        // Generate sine wave
        let frameCount = Int(sampleRate * duration)
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channelData = buffer.floatChannelData {
            for i in 0..<frameCount {
                let phase = 2.0 * Float.pi * frequency * Float(i) / Float(sampleRate)
                channelData[0][i] = sin(phase)
            }
        }

        let features = try await extractor.extract(from: buffer)

        XCTAssertEqual(features.count, extractor.featureCount)
        XCTAssertTrue(features.allSatisfy { $0.isFinite })
    }
}
