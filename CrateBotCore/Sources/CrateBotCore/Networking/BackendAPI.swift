import Foundation

/// Namespace for backend API request and response types
public enum BackendAPI {

    // MARK: - Vibe Request/Response

    /// Request to generate vibe for a single file
    public struct VibeRequest: Codable, Sendable {
        public let filePath: String
        public let overwrite: Bool
        public let dryRun: Bool
        public let skipHook: Bool

        public init(
            filePath: String,
            overwrite: Bool = false,
            dryRun: Bool = false,
            skipHook: Bool = false
        ) {
            self.filePath = filePath
            self.overwrite = overwrite
            self.dryRun = dryRun
            self.skipHook = skipHook
        }
    }

    /// Result of vibe generation
    public struct VibeResponse: Codable, Sendable {
        public let filePath: String
        public let filename: String
        public let status: String
        public let vibe: String?
        public let description: String?
        public let scene: String?
        public let sceneConfidence: Double?
        public let hook: String?
        public let hookOccurrences: Int?
        public let detections: String?
        public let error: String?

        public init(
            filePath: String,
            filename: String,
            status: String,
            vibe: String? = nil,
            description: String? = nil,
            scene: String? = nil,
            sceneConfidence: Double? = nil,
            hook: String? = nil,
            hookOccurrences: Int? = nil,
            detections: String? = nil,
            error: String? = nil
        ) {
            self.filePath = filePath
            self.filename = filename
            self.status = status
            self.vibe = vibe
            self.description = description
            self.scene = scene
            self.sceneConfidence = sceneConfidence
            self.hook = hook
            self.hookOccurrences = hookOccurrences
            self.detections = detections
            self.error = error
        }
    }

    // MARK: - Hook Request/Response

    /// Request for hook transcription
    public struct HookRequest: Codable, Sendable {
        public let filePath: String
        public let artist: String?
        public let title: String?

        public init(
            filePath: String,
            artist: String? = nil,
            title: String? = nil
        ) {
            self.filePath = filePath
            self.artist = artist
            self.title = title
        }
    }

    /// Result of hook transcription
    public struct HookResponse: Codable, Sendable {
        public let hook: String?
        public let confidence: Double
        public let occurrences: Int
        public let transcription: String?
        public let lyricsVerified: Bool?

        public init(
            hook: String? = nil,
            confidence: Double = 0.0,
            occurrences: Int = 0,
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

    // MARK: - Health Response

    /// Health check response from the backend
    public struct HealthResponse: Codable, Sendable {
        public let status: String
        public let modelLoaded: Bool
        public let modelLoading: Bool?
        public let tagManagerReady: Bool?
        public let tagManagerError: String?

        public init(
            status: String,
            modelLoaded: Bool,
            modelLoading: Bool? = nil,
            tagManagerReady: Bool? = nil,
            tagManagerError: String? = nil
        ) {
            self.status = status
            self.modelLoaded = modelLoaded
            self.modelLoading = modelLoading
            self.tagManagerReady = tagManagerReady
            self.tagManagerError = tagManagerError
        }
    }

    // MARK: - Settings Response

    /// Settings response from the backend
    public struct SettingsResponse: Codable, Sendable {
        public let anthropicApiKeySet: Bool
        public let modelsDirectory: String
        public let cacheDirectory: String
        public let vibeAvailable: Bool
        public let vibeStatus: String
        public let hookAvailable: Bool
        public let hookStatus: String
        public let pannsAvailable: Bool?

        public init(
            anthropicApiKeySet: Bool,
            modelsDirectory: String,
            cacheDirectory: String,
            vibeAvailable: Bool,
            vibeStatus: String,
            hookAvailable: Bool,
            hookStatus: String,
            pannsAvailable: Bool? = nil
        ) {
            self.anthropicApiKeySet = anthropicApiKeySet
            self.modelsDirectory = modelsDirectory
            self.cacheDirectory = cacheDirectory
            self.vibeAvailable = vibeAvailable
            self.vibeStatus = vibeStatus
            self.hookAvailable = hookAvailable
            self.hookStatus = hookStatus
            self.pannsAvailable = pannsAvailable
        }
    }

    // MARK: - API Key Request

    /// Request to set the Anthropic API key
    public struct APIKeyRequest: Codable, Sendable {
        public let apiKey: String

        public init(apiKey: String) {
            self.apiKey = apiKey
        }
    }

    /// Response after setting API key
    public struct APIKeyResponse: Codable, Sendable {
        public let status: String
        public let message: String

        public init(status: String, message: String) {
            self.status = status
            self.message = message
        }
    }
}
