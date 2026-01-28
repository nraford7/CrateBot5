import Foundation
import os.log

/// Detects memorable vocal hooks using lyrics-first approach with Whisper fallback
public actor HookDetector {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "HookDetector")
    private let httpClient: HTTPClient

    public init(httpClient: HTTPClient? = nil) {
        self.httpClient = httpClient ?? HTTPClient()
    }

    public enum HookError: Error, LocalizedError, Sendable {
        case backendUnavailable
        case detectionFailed(String)
        case whisperNotAvailable
        case noVocalsDetected
        case invalidFile(String)

        public var errorDescription: String? {
            switch self {
            case .backendUnavailable:
                return "Backend server is not available"
            case .detectionFailed(let message):
                return "Hook detection failed: \(message)"
            case .whisperNotAvailable:
                return "Whisper model is not available"
            case .noVocalsDetected:
                return "No vocals detected in track"
            case .invalidFile(let message):
                return "Invalid file: \(message)"
            }
        }
    }

    /// Result of hook detection
    public struct HookResult: Sendable {
        public let hook: String?              // The detected hook phrase
        public let confidence: Double         // 0.0 - 1.0
        public let occurrences: Int           // How many times it repeats
        public let transcription: String?     // Full transcribed vocals
        public let lyricsVerified: Bool?      // Verified against lyrics database

        public var hasHook: Bool { hook != nil && confidence > 0.5 }

        public init(
            hook: String?,
            confidence: Double,
            occurrences: Int,
            transcription: String? = nil,
            lyricsVerified: Bool? = nil
        ) {
            self.hook = hook
            self.confidence = confidence
            self.occurrences = occurrences
            self.transcription = transcription
            self.lyricsVerified = lyricsVerified
        }
    }

    /// Check if hook detection is available
    public func isAvailable() async -> Bool {
        guard await httpClient.healthCheck() else { return false }

        do {
            let settings: BackendAPI.SettingsResponse = try await httpClient.get(path: "/api/v1/settings")
            return settings.hookAvailable
        } catch {
            logger.warning("Failed to check hook availability: \(error.localizedDescription)")
            return false
        }
    }

    /// Detect hook in an audio file
    public func detectHook(
        in fileURL: URL,
        artist: String? = nil,
        title: String? = nil
    ) async throws -> HookResult {
        // Validate file
        guard fileURL.isFileURL else {
            throw HookError.invalidFile("Not a file URL")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw HookError.invalidFile("File does not exist: \(fileURL.lastPathComponent)")
        }

        guard await httpClient.healthCheck() else {
            throw HookError.backendUnavailable
        }

        let request = BackendAPI.HookRequest(
            filePath: fileURL.path,
            artist: artist,
            title: title
        )

        do {
            let response: BackendAPI.HookResponse = try await httpClient.post(
                path: "/api/v1/hook/detect",
                body: request
            )

            if let hook = response.hook {
                logger.info("Detected hook in \(fileURL.lastPathComponent): \"\(hook)\" (confidence: \(response.confidence))")
            } else {
                logger.debug("No hook detected in \(fileURL.lastPathComponent)")
            }

            return HookResult(
                hook: response.hook,
                confidence: response.confidence,
                occurrences: response.occurrences,
                transcription: response.transcription,
                lyricsVerified: response.lyricsVerified
            )
        } catch let error as HTTPError {
            switch error {
            case .serverNotRunning:
                throw HookError.backendUnavailable
            case .requestFailed(let code, let message):
                if code == 503 && message.contains("Whisper") {
                    throw HookError.whisperNotAvailable
                }
                if message.contains("no vocals") {
                    throw HookError.noVocalsDetected
                }
                throw HookError.detectionFailed(message)
            default:
                throw HookError.detectionFailed(error.localizedDescription)
            }
        }
    }
}
