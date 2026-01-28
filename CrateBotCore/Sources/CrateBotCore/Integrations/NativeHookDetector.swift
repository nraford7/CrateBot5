import Foundation
import Speech
import AVFoundation
import os.log

// MARK: - Error Types

/// Errors that can occur during native hook detection
public enum NativeHookError: Error, LocalizedError, Sendable {
    case speechRecognitionUnavailable
    case authorizationDenied
    case noVocalsDetected
    case transcriptionFailed(String)
    case fileNotFound(String)
    case audioLoadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this device"
        case .authorizationDenied:
            return "Speech recognition authorization was denied"
        case .noVocalsDetected:
            return "No vocals were detected in the audio"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .audioLoadFailed(let message):
            return "Failed to load audio: \(message)"
        }
    }
}

// MARK: - Data Types

/// Result of hook detection
public struct HookResult: Sendable {
    public let hook: String?
    public let confidence: Double
    public let occurrences: Int
    public let transcription: String?

    /// Returns true if a hook was detected with sufficient confidence
    public var hasHook: Bool {
        hook != nil && confidence >= 0.5
    }

    public init(
        hook: String?,
        confidence: Double,
        occurrences: Int,
        transcription: String? = nil
    ) {
        self.hook = hook
        self.confidence = confidence
        self.occurrences = occurrences
        self.transcription = transcription
    }
}

/// A phrase detected in the audio transcription
public struct DetectedPhrase: Sendable {
    public let phrase: String
    public let count: Int
    public let confidence: Double

    public init(phrase: String, count: Int, confidence: Double) {
        self.phrase = phrase
        self.count = count
        self.confidence = confidence
    }
}

// MARK: - Native Hook Detector

/// Actor for detecting vocal hooks in audio using Apple's Speech framework
public actor NativeHookDetector {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "NativeHookDetector")
    private var cache: [String: HookResult] = [:]

    /// Initialize the hook detector
    public init() {}

    /// Check if speech recognition is available (nonisolated for synchronous access)
    public nonisolated var isAvailable: Bool {
        SFSpeechRecognizer()?.isAvailable ?? false
    }

    /// Request authorization for speech recognition
    /// - Returns: True if authorization was granted
    public func requestAuthorization() async -> Bool {
        // Check current status first to avoid unnecessary prompts
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        if currentStatus == .authorized {
            return true
        }
        if currentStatus == .denied || currentStatus == .restricted {
            return false
        }

        // Only request if not determined
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Detect a hook in an audio file
    /// - Parameters:
    ///   - fileURL: URL to the audio file
    ///   - cacheKey: Optional key for caching results
    /// - Returns: The detected hook result
    public func detectHook(in fileURL: URL, cacheKey: String? = nil) async throws -> HookResult {
        // Check cache first
        if let key = cacheKey, let cached = cache[key] {
            logger.debug("Returning cached hook for key: \(key)")
            return cached
        }

        // Validate file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NativeHookError.fileNotFound(fileURL.path)
        }

        // Check availability
        guard isAvailable else {
            throw NativeHookError.speechRecognitionUnavailable
        }

        // Request authorization if needed
        let authorized = await requestAuthorization()
        guard authorized else {
            throw NativeHookError.authorizationDenied
        }

        // Create speech recognizer
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw NativeHookError.speechRecognitionUnavailable
        }

        logger.info("Starting transcription for: \(fileURL.lastPathComponent)")

        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        // Perform recognition
        let transcription: String
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let result = result, result.isFinal else {
                        return
                    }

                    continuation.resume(returning: result)
                }
            }

            transcription = result.bestTranscription.formattedString
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            throw NativeHookError.transcriptionFailed(error.localizedDescription)
        }

        // Check if we got any transcription
        guard !transcription.isEmpty else {
            logger.info("No vocals detected in: \(fileURL.lastPathComponent)")
            throw NativeHookError.noVocalsDetected
        }

        logger.debug("Transcription: \(transcription)")

        // Extract repeated phrases
        let phrases = Self.extractRepeatedPhrases(from: transcription)

        // Build result
        let result: HookResult
        if let topPhrase = phrases.first {
            logger.info("Detected hook: \"\(topPhrase.phrase)\" with confidence \(topPhrase.confidence)")
            result = HookResult(
                hook: topPhrase.phrase,
                confidence: topPhrase.confidence,
                occurrences: topPhrase.count,
                transcription: transcription
            )
        } else {
            logger.info("No repeated phrases found in transcription")
            result = HookResult(
                hook: nil,
                confidence: 0.0,
                occurrences: 0,
                transcription: transcription
            )
        }

        // Cache the result if a key was provided
        if let key = cacheKey {
            cache[key] = result
            logger.debug("Cached hook for key: \(key)")
        }

        return result
    }

    /// Clear the in-memory cache
    public func clearCache() {
        cache.removeAll()
        logger.info("Cache cleared")
    }

    // MARK: - Static Methods

    /// Extract repeated phrases from transcribed text
    /// - Parameter text: The transcribed text to analyze
    /// - Returns: Array of detected phrases sorted by confidence (descending), limited to top 5
    public static func extractRepeatedPhrases(from text: String) -> [DetectedPhrase] {
        // Split text into lowercase words
        let words = text.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard words.count >= 3 else {
            return []
        }

        // Count n-grams of lengths 3-6
        var phraseCounts: [String: Int] = [:]

        for length in 3...6 {
            guard words.count >= length else { continue }

            for i in 0...(words.count - length) {
                let ngram = words[i..<(i + length)].joined(separator: " ")
                phraseCounts[ngram, default: 0] += 1
            }
        }

        // Filter to phrases with 2+ occurrences
        let repeatedPhrases = phraseCounts.filter { $0.value >= 2 }

        guard !repeatedPhrases.isEmpty else {
            return []
        }

        // Calculate confidence for each phrase
        let detectedPhrases = repeatedPhrases.map { phrase, count -> DetectedPhrase in
            let wordCount = phrase.components(separatedBy: " ").count

            // Length bonus: longer phrases get higher scores (3 words = 0.25, 6 words = 1.0)
            let lengthBonus = Double(wordCount - 2) / 4.0

            // Repetition bonus: more occurrences = higher confidence (2 = 0.5, 4+ = 1.0)
            let repetitionBonus = min(1.0, Double(count - 1) / 3.0)

            // Combined confidence
            let confidence = (lengthBonus + repetitionBonus) / 2.0

            return DetectedPhrase(
                phrase: phrase,
                count: count,
                confidence: confidence
            )
        }

        // Sort by confidence descending and return top 5
        return detectedPhrases
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .map { $0 }
    }
}
