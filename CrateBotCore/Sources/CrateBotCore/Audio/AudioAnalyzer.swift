import AVFoundation
import os.log

public final class AudioAnalyzer: Sendable {
    public let targetSampleRate: Double = 22050
    private let chunkSize: AVAudioFrameCount = 8192
    private let logger = Logger(subsystem: "com.cratebot", category: "AudioAnalyzer")
    private let segmentDedupEpsilon: Double = 0.5

    public enum AnalyzerError: Error, LocalizedError {
        case fileReadFailed(URL)
        case formatCreationFailed
        case converterCreationFailed
        case conversionFailed(String)
        case bufferCreationFailed
        case fileTooLong(URL, duration: Double)
        case bufferOverflow(URL, requiredBytes: UInt64)
        case audioTooShort(URL, duration: Double, required: Double)

        public var errorDescription: String? {
            switch self {
            case .fileReadFailed(let url):
                return "Failed to read audio file: \(url.lastPathComponent)"
            case .formatCreationFailed:
                return "Failed to create audio format"
            case .converterCreationFailed:
                return "Failed to create audio converter"
            case .conversionFailed(let reason):
                return "Audio conversion failed: \(reason)"
            case .bufferCreationFailed:
                return "Failed to create audio buffer"
            case .fileTooLong(let url, let duration):
                return "Audio file too long: \(url.lastPathComponent) (\(Int(duration/60))min) - max 30 minutes"
            case .bufferOverflow(let url, let requiredBytes):
                let mbRequired = Double(requiredBytes) / 1_000_000
                return "Audio file too large: \(url.lastPathComponent) requires \(String(format: "%.0f", mbRequired))MB buffer"
            case .audioTooShort(let url, let duration, let required):
                return "Audio too short: \(url.lastPathComponent) (\(String(format: "%.1f", duration))s) - needs \(String(format: "%.1f", required))s minimum"
            }
        }
    }

    /// Result of validating an audio file for processing
    public struct ValidationResult: Sendable {
        public let url: URL
        public let isValid: Bool
        public let error: AnalyzerError?
        public let duration: Double?
        public let sampleRate: Double?
        public let channels: UInt32?
        public let estimatedBufferSize: UInt64?

        public init(
            url: URL,
            isValid: Bool,
            error: AnalyzerError? = nil,
            duration: Double? = nil,
            sampleRate: Double? = nil,
            channels: UInt32? = nil,
            estimatedBufferSize: UInt64? = nil
        ) {
            self.url = url
            self.isValid = isValid
            self.error = error
            self.duration = duration
            self.sampleRate = sampleRate
            self.channels = channels
            self.estimatedBufferSize = estimatedBufferSize
        }
    }

    /// Maximum audio duration in seconds (30 minutes)
    private let maxDurationSeconds: Double = 30 * 60

    /// Maximum buffer size in bytes (UInt32.max)
    private let maxBufferBytes: UInt64 = UInt64(UInt32.max)

    /// Minimum audio duration in seconds for EffNet processing
    /// EffNet needs 128 time frames with hopSize=256 at 16kHz
    /// Required samples = (127 * 256) + 512 = 33,024 samples = 2.064 seconds
    public static let minimumDurationSeconds: Double = 2.1

    public init() {}

    /// Validate an audio file before processing to check for potential issues
    /// - Parameter url: URL of the audio file to validate
    /// - Returns: ValidationResult indicating if the file can be safely processed
    public func validateFile(at url: URL) -> ValidationResult {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            return ValidationResult(
                url: url,
                isValid: false,
                error: .fileReadFailed(url)
            )
        }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channels = format.channelCount

        // Guard against invalid format data
        guard sampleRate > 0, channels > 0, file.length > 0 else {
            return ValidationResult(
                url: url,
                isValid: false,
                error: .fileReadFailed(url)
            )
        }

        let durationSeconds = Double(file.length) / sampleRate

        // Check minimum duration for EffNet processing
        if durationSeconds < Self.minimumDurationSeconds {
            return ValidationResult(
                url: url,
                isValid: false,
                error: .audioTooShort(url, duration: durationSeconds, required: Self.minimumDurationSeconds),
                duration: durationSeconds,
                sampleRate: sampleRate,
                channels: channels
            )
        }

        // Check maximum duration limit
        if durationSeconds > maxDurationSeconds {
            return ValidationResult(
                url: url,
                isValid: false,
                error: .fileTooLong(url, duration: durationSeconds),
                duration: durationSeconds,
                sampleRate: sampleRate,
                channels: channels
            )
        }

        // Check frame count overflow (Int64 -> UInt32)
        if file.length > Int64(UInt32.max) {
            return ValidationResult(
                url: url,
                isValid: false,
                error: .fileTooLong(url, duration: durationSeconds),
                duration: durationSeconds,
                sampleRate: sampleRate,
                channels: channels
            )
        }

        // Check buffer size overflow (frameCount * bytesPerFrame * channels for non-interleaved)
        let bytesPerFrame = UInt64(format.streamDescription.pointee.mBytesPerFrame)
        let channelCount64 = UInt64(channels)
        let frameBytes = format.isInterleaved ? bytesPerFrame : bytesPerFrame * channelCount64
        let totalBytes = UInt64(file.length) * frameBytes

        if totalBytes > maxBufferBytes {
            return ValidationResult(
                url: url,
                isValid: false,
                error: .bufferOverflow(url, requiredBytes: totalBytes),
                duration: durationSeconds,
                sampleRate: sampleRate,
                channels: channels,
                estimatedBufferSize: totalBytes
            )
        }

        // File is valid
        return ValidationResult(
            url: url,
            isValid: true,
            duration: durationSeconds,
            sampleRate: sampleRate,
            channels: channels,
            estimatedBufferSize: totalBytes
        )
    }

    /// Validate multiple audio files concurrently
    /// - Parameter urls: URLs of audio files to validate
    /// - Returns: Array of validation results
    public func validateFiles(at urls: [URL]) async -> [ValidationResult] {
        await withTaskGroup(of: ValidationResult.self) { group in
            for url in urls {
                group.addTask {
                    self.validateFile(at: url)
                }
            }

            var results: [ValidationResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Extract PCM buffer from audio file, converting to mono 22050Hz
    public func extractPCMBuffer(from url: URL) throws -> AVAudioPCMBuffer {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AnalyzerError.fileReadFailed(url)
        }

        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: 1
        ) else {
            throw AnalyzerError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
            throw AnalyzerError.formatCreationFailed
        }

        let outputFrameCount = AVAudioFrameCount(
            Double(file.length) * targetSampleRate / file.processingFormat.sampleRate
        )

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            throw AnalyzerError.bufferCreationFailed
        }

        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: chunkSize
        ) else {
            throw AnalyzerError.bufferCreationFailed
        }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
            do {
                try file.read(into: inputBuffer, frameCount: min(inNumPackets, self.chunkSize))

                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        if status == .error {
            throw AnalyzerError.conversionFailed(conversionError?.localizedDescription ?? "Unknown error")
        }

        logger.debug("Extracted \(outputBuffer.frameLength) frames from \(url.lastPathComponent)")
        return outputBuffer
    }

    /// Get raw float samples from buffer
    public func getSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    /// Load and resample audio to target sample rate
    /// - Parameters:
    ///   - url: URL of the audio file
    ///   - targetSampleRate: Desired sample rate (default 16000 for EffNet)
    /// - Returns: Mono audio buffer at the target sample rate
    public func loadAudio(from url: URL, targetSampleRate: Double = 16000) async throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat

        // Load source audio as mono
        let sourceBuffer = try loadMonoBuffer(from: file)

        // If already at target rate, return directly
        if sourceFormat.sampleRate == targetSampleRate {
            return sourceBuffer
        }

        // Create output format at target sample rate
        guard let targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: 1
        ) else {
            throw AnalyzerError.formatCreationFailed
        }

        // Create converter
        guard let converter = AVAudioConverter(from: sourceBuffer.format, to: targetFormat) else {
            throw AnalyzerError.converterCreationFailed
        }

        // Calculate output frame count
        let ratio = targetSampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else {
            throw AnalyzerError.bufferCreationFailed
        }

        // Track conversion state
        var inputConsumed = false

        // Convert
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let error = error {
            throw AnalyzerError.conversionFailed(error.localizedDescription)
        }

        if status == .error {
            throw AnalyzerError.conversionFailed("Conversion returned error status")
        }

        return outputBuffer
    }

    /// Load multiple segments from an audio file and resample them to the target sample rate.
    /// Segments are defined by start fractions of the total duration and a fixed duration.
    public func loadAudioSegments(
        from url: URL,
        targetSampleRate: Double = 16000,
        segmentDuration: Double,
        startFractions: [Double]
    ) async throws -> [AVAudioPCMBuffer] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let durationSeconds = Double(file.length) / sourceFormat.sampleRate

        let starts = normalizedSegmentStarts(
            durationSeconds: durationSeconds,
            segmentDuration: segmentDuration,
            startFractions: startFractions
        )

        var buffers: [AVAudioPCMBuffer] = []
        buffers.reserveCapacity(starts.count)

        for start in starts {
            let startFrame = AVAudioFramePosition(start * sourceFormat.sampleRate)
            let maxFrames = AVAudioFrameCount(min(
                segmentDuration * sourceFormat.sampleRate,
                Double(max(0, file.length - startFrame))
            ))

            guard maxFrames > 0 else { continue }

            let segmentBuffer = try loadMonoBufferSegment(
                from: file,
                startFrame: startFrame,
                frameCount: maxFrames
            )

            let resampled = try resampleIfNeeded(
                buffer: segmentBuffer,
                sourceSampleRate: sourceFormat.sampleRate,
                targetSampleRate: targetSampleRate
            )

            buffers.append(resampled)
        }

        return buffers
    }

    private func loadMonoBuffer(from file: AVAudioFile) throws -> AVAudioPCMBuffer {
        let format = file.processingFormat

        // Check for files that are too long (could cause integer overflow or memory issues)
        let durationSeconds = Double(file.length) / format.sampleRate
        if durationSeconds > maxDurationSeconds {
            throw AnalyzerError.fileTooLong(file.url, duration: durationSeconds)
        }

        // Safely convert frame count (file.length is Int64, AVAudioFrameCount is UInt32)
        guard file.length <= Int64(UInt32.max) else {
            throw AnalyzerError.fileTooLong(file.url, duration: durationSeconds)
        }

        // AVAudioPCMBuffer internally calculates frameCount * bytesPerFrame
        // This can overflow UInt32 for large files, causing a crash
        // Check that the total byte size won't overflow (account for non-interleaved channels)
        let bytesPerFrame = UInt64(format.streamDescription.pointee.mBytesPerFrame)
        let channels = UInt64(format.channelCount)
        let frameBytes = format.isInterleaved ? bytesPerFrame : bytesPerFrame * channels
        let totalBytes = UInt64(file.length) * frameBytes
        guard totalBytes <= UInt64(UInt32.max) else {
            logger.warning("File too large: \(file.url.lastPathComponent) would require \(totalBytes) bytes")
            throw AnalyzerError.fileTooLong(file.url, duration: durationSeconds)
        }

        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AnalyzerError.bufferCreationFailed
        }

        try file.read(into: buffer)

        // If already mono, return as-is
        if format.channelCount == 1 {
            return buffer
        }

        // Convert stereo to mono
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1),
              let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCount) else {
            throw AnalyzerError.bufferCreationFailed
        }

        monoBuffer.frameLength = buffer.frameLength

        // Average channels
        guard let sourceData = buffer.floatChannelData,
              let destData = monoBuffer.floatChannelData else {
            throw AnalyzerError.bufferCreationFailed
        }

        let channelCount = Int(format.channelCount)
        for i in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += sourceData[ch][i]
            }
            destData[0][i] = sum / Float(channelCount)
        }

        return monoBuffer
    }

    private func loadMonoBufferSegment(
        from file: AVAudioFile,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        let format = file.processingFormat
        let totalFrames = file.length

        guard startFrame >= 0, startFrame < totalFrames else {
            throw AnalyzerError.fileReadFailed(file.url)
        }

        let clampedFrameCount = AVAudioFrameCount(
            min(Int64(frameCount), totalFrames - startFrame)
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: clampedFrameCount
        ) else {
            throw AnalyzerError.bufferCreationFailed
        }

        file.framePosition = startFrame
        try file.read(into: buffer, frameCount: clampedFrameCount)

        // If already mono, return as-is
        if format.channelCount == 1 {
            return buffer
        }

        // Convert to mono
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1),
              let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameCapacity) else {
            throw AnalyzerError.bufferCreationFailed
        }

        monoBuffer.frameLength = buffer.frameLength

        guard let sourceData = buffer.floatChannelData,
              let destData = monoBuffer.floatChannelData else {
            throw AnalyzerError.bufferCreationFailed
        }

        let channelCount = Int(format.channelCount)
        for i in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += sourceData[ch][i]
            }
            destData[0][i] = sum / Float(channelCount)
        }

        return monoBuffer
    }

    private func resampleIfNeeded(
        buffer: AVAudioPCMBuffer,
        sourceSampleRate: Double,
        targetSampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        if sourceSampleRate == targetSampleRate {
            return buffer
        }

        guard let targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: 1
        ) else {
            throw AnalyzerError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            throw AnalyzerError.converterCreationFailed
        }

        let ratio = targetSampleRate / sourceSampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else {
            throw AnalyzerError.bufferCreationFailed
        }

        var inputConsumed = false
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            throw AnalyzerError.conversionFailed(error.localizedDescription)
        }

        if status == .error {
            throw AnalyzerError.conversionFailed("Conversion returned error status")
        }

        return outputBuffer
    }

    private func normalizedSegmentStarts(
        durationSeconds: Double,
        segmentDuration: Double,
        startFractions: [Double]
    ) -> [Double] {
        guard durationSeconds > 0 else { return [] }

        if durationSeconds <= segmentDuration {
            return [0.0]
        }

        var starts: [Double] = []
        starts.reserveCapacity(startFractions.count)

        for fraction in startFractions {
            let rawStart = max(0.0, min(1.0, fraction)) * durationSeconds
            let clampedStart = min(rawStart, durationSeconds - segmentDuration)

            // Deduplicate near-identical starts (short tracks can clamp multiple fractions)
            if starts.contains(where: { abs($0 - clampedStart) < segmentDedupEpsilon }) {
                continue
            }

            starts.append(clampedStart)
        }

        return starts
    }
}
