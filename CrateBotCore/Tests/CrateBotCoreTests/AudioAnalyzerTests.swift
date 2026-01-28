import XCTest
import AVFoundation
@testable import CrateBotCore

final class AudioAnalyzerTests: XCTestCase {
    var analyzer: AudioAnalyzer!

    override func setUp() {
        analyzer = AudioAnalyzer()
    }

    func testTargetSampleRate() {
        XCTAssertEqual(analyzer.targetSampleRate, 22050)
    }

    func testExtractBufferFromNonexistentFile() async {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/file.mp3")

        do {
            _ = try analyzer.extractPCMBuffer(from: fakeURL)
            XCTFail("Should throw for nonexistent file")
        } catch {
            // Expected
        }
    }

    func testResampleTo16kHz() async throws {
        // Create a synthetic 44.1kHz audio buffer
        let sourceSampleRate: Double = 44100
        let duration: Double = 0.5
        let frequency: Double = 440.0
        let sampleCount = Int(sourceSampleRate * duration)

        let samples = (0..<sampleCount).map { i in
            Float(sin(2.0 * .pi * frequency * Double(i) / sourceSampleRate))
        }

        // Create temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_audio_\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Write to file - use do block to ensure file is closed before reading
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 1)!
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
            sourceBuffer.frameLength = AVAudioFrameCount(sampleCount)
            memcpy(sourceBuffer.floatChannelData![0], samples, sampleCount * MemoryLayout<Float>.size)

            let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            try audioFile.write(from: sourceBuffer)
            // audioFile is released here, ensuring file is flushed
        }

        // Test resampling
        let analyzer = AudioAnalyzer()
        let resampledBuffer = try await analyzer.loadAudio(from: tempURL, targetSampleRate: 16000)

        XCTAssertEqual(resampledBuffer.format.sampleRate, 16000, "Should resample to 16kHz")
        XCTAssertEqual(resampledBuffer.format.channelCount, 1, "Should be mono")

        // Check approximate frame count (allowing for rounding and resampling variance)
        // Resampling can have variance due to filter delay and algorithm differences
        let expectedFrames = Int(16000 * duration)
        let actualFrames = Int(resampledBuffer.frameLength)
        XCTAssertEqual(actualFrames, expectedFrames, accuracy: 250, "Frame count should be approximately correct")
    }

    // MARK: - Validation Tests

    func testValidateValidAudioFile() throws {
        // Create a valid short audio file
        let sourceSampleRate: Double = 44100
        let duration: Double = 1.0  // 1 second
        let sampleCount = Int(sourceSampleRate * duration)

        let samples = (0..<sampleCount).map { i in
            Float(sin(2.0 * .pi * 440.0 * Double(i) / sourceSampleRate))
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("valid_audio_\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Write to file - use do block to ensure file is closed before validation
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 1)!
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
            sourceBuffer.frameLength = AVAudioFrameCount(sampleCount)
            memcpy(sourceBuffer.floatChannelData![0], samples, sampleCount * MemoryLayout<Float>.size)

            let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            try audioFile.write(from: sourceBuffer)
            // audioFile is released here, ensuring file is flushed
        }

        // Test validation
        let result = analyzer.validateFile(at: tempURL)

        XCTAssertTrue(result.isValid, "Valid audio file should pass validation")
        XCTAssertNil(result.error, "Valid file should have no error")
        XCTAssertNotNil(result.duration, "Should report duration")
        XCTAssertNotNil(result.sampleRate, "Should report sample rate")
        XCTAssertNotNil(result.channels, "Should report channels")
        XCTAssertEqual(result.sampleRate, sourceSampleRate, "Should report correct sample rate")
        XCTAssertEqual(result.channels, 1, "Should report correct channel count")
    }

    func testValidateNonExistentFile() {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/file.mp3")

        let result = analyzer.validateFile(at: fakeURL)

        XCTAssertFalse(result.isValid, "Non-existent file should fail validation")
        XCTAssertNotNil(result.error, "Should have an error")
        if case .fileReadFailed = result.error {
            // Expected error type
        } else {
            XCTFail("Expected fileReadFailed error")
        }
    }

    func testValidateFilesAsync() async throws {
        // Create two valid audio files
        let sourceSampleRate: Double = 44100
        let sampleCount = Int(sourceSampleRate * 0.5)  // 0.5 seconds

        let samples = (0..<sampleCount).map { i in
            Float(sin(2.0 * .pi * 440.0 * Double(i) / sourceSampleRate))
        }

        let tempURL1 = FileManager.default.temporaryDirectory.appendingPathComponent("valid_audio1_\(UUID()).wav")
        let tempURL2 = FileManager.default.temporaryDirectory.appendingPathComponent("valid_audio2_\(UUID()).wav")
        defer {
            try? FileManager.default.removeItem(at: tempURL1)
            try? FileManager.default.removeItem(at: tempURL2)
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 1)!

        // Create file 1
        do {
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
            sourceBuffer.frameLength = AVAudioFrameCount(sampleCount)
            memcpy(sourceBuffer.floatChannelData![0], samples, sampleCount * MemoryLayout<Float>.size)
            let audioFile = try AVAudioFile(forWriting: tempURL1, settings: format.settings)
            try audioFile.write(from: sourceBuffer)
        }

        // Create file 2
        do {
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
            sourceBuffer.frameLength = AVAudioFrameCount(sampleCount)
            memcpy(sourceBuffer.floatChannelData![0], samples, sampleCount * MemoryLayout<Float>.size)
            let audioFile = try AVAudioFile(forWriting: tempURL2, settings: format.settings)
            try audioFile.write(from: sourceBuffer)
        }

        // Test bulk validation
        let results = await analyzer.validateFiles(at: [tempURL1, tempURL2])

        XCTAssertEqual(results.count, 2, "Should return results for both files")

        let validCount = results.filter { $0.isValid }.count
        XCTAssertEqual(validCount, 2, "Both files should be valid")
    }

    func testValidationResultProperties() {
        // Test ValidationResult initialization and properties
        let url = URL(fileURLWithPath: "/test/file.mp3")

        let validResult = AudioAnalyzer.ValidationResult(
            url: url,
            isValid: true,
            error: nil,
            duration: 120.0,
            sampleRate: 44100,
            channels: 2,
            estimatedBufferSize: 1024 * 1024
        )

        XCTAssertEqual(validResult.url, url)
        XCTAssertTrue(validResult.isValid)
        XCTAssertNil(validResult.error)
        XCTAssertEqual(validResult.duration, 120.0)
        XCTAssertEqual(validResult.sampleRate, 44100)
        XCTAssertEqual(validResult.channels, 2)
        XCTAssertEqual(validResult.estimatedBufferSize, 1024 * 1024)

        let invalidResult = AudioAnalyzer.ValidationResult(
            url: url,
            isValid: false,
            error: .fileTooLong(url, duration: 3600),
            duration: 3600,
            sampleRate: 44100,
            channels: 1
        )

        XCTAssertFalse(invalidResult.isValid)
        XCTAssertNotNil(invalidResult.error)
    }

    // MARK: - AnalyzerError Tests

    func testAnalyzerErrorDescriptions() {
        let url = URL(fileURLWithPath: "/test/file.mp3")

        XCTAssertEqual(
            AudioAnalyzer.AnalyzerError.fileReadFailed(url).errorDescription,
            "Failed to read audio file: file.mp3"
        )

        XCTAssertEqual(
            AudioAnalyzer.AnalyzerError.formatCreationFailed.errorDescription,
            "Failed to create audio format"
        )

        XCTAssertEqual(
            AudioAnalyzer.AnalyzerError.converterCreationFailed.errorDescription,
            "Failed to create audio converter"
        )

        XCTAssertEqual(
            AudioAnalyzer.AnalyzerError.conversionFailed("Test reason").errorDescription,
            "Audio conversion failed: Test reason"
        )

        XCTAssertEqual(
            AudioAnalyzer.AnalyzerError.bufferCreationFailed.errorDescription,
            "Failed to create audio buffer"
        )

        // Test fileTooLong error (30 minutes = 1800 seconds)
        let fileTooLongError = AudioAnalyzer.AnalyzerError.fileTooLong(url, duration: 1800)
        XCTAssertTrue(fileTooLongError.errorDescription?.contains("30min") ?? false)

        // Test bufferOverflow error
        let bufferOverflowError = AudioAnalyzer.AnalyzerError.bufferOverflow(url, requiredBytes: 5_000_000_000)
        XCTAssertTrue(bufferOverflowError.errorDescription?.contains("5000") ?? false)
    }

    func testValidateStereoFile() throws {
        // Create a stereo audio file using standard format (non-interleaved)
        let sourceSampleRate: Double = 44100
        let duration: Double = 0.5  // Short file
        let sampleCount = Int(sourceSampleRate * duration)

        let samples = (0..<sampleCount).map { i in
            Float(sin(2.0 * .pi * 440.0 * Double(i) / sourceSampleRate))
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("stereo_audio_\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Write stereo file - use do block to ensure file is closed before validation
        do {
            // Use standardFormat which is non-interleaved but write with settings that work
            let format = AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 2)!
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
            sourceBuffer.frameLength = AVAudioFrameCount(sampleCount)

            // Fill both channels (non-interleaved: separate arrays)
            if let channelData = sourceBuffer.floatChannelData {
                for channel in 0..<2 {
                    for i in 0..<sampleCount {
                        channelData[channel][i] = samples[i]
                    }
                }
            }

            // Write with Linear PCM settings to avoid format issues
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: sourceSampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
            try audioFile.write(from: sourceBuffer)
            // audioFile is released here, ensuring file is flushed
        }

        // Test validation
        let result = analyzer.validateFile(at: tempURL)

        XCTAssertTrue(result.isValid, "Stereo file should pass validation")
        XCTAssertEqual(result.channels, 2, "Should report 2 channels")
    }
}
