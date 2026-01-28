import Foundation
import os.log

/// Errors that can occur during vibe generation
public enum VibeError: Error, LocalizedError, Sendable {
    case backendUnavailable
    case generationFailed(String)
    case apiKeyNotConfigured
    case invalidFile(String)
    case apiKeyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .backendUnavailable:
            return "Backend server is not available"
        case .generationFailed(let message):
            return "Vibe generation failed: \(message)"
        case .apiKeyNotConfigured:
            return "Anthropic API key is not configured"
        case .invalidFile(let message):
            return "Invalid file: \(message)"
        case .apiKeyFailed(let message):
            return "Failed to set API key: \(message)"
        }
    }
}

/// Result of vibe generation
public struct VibeResult: Sendable {
    public let vibe: String
    public let description: String?
    public let hook: String?
    public let hookConfidence: Double?
    public let scene: String?
    public let sceneConfidence: Double?
    public let cached: Bool

    public init(
        vibe: String,
        description: String? = nil,
        hook: String? = nil,
        hookConfidence: Double? = nil,
        scene: String? = nil,
        sceneConfidence: Double? = nil,
        cached: Bool = false
    ) {
        self.vibe = vibe
        self.description = description
        self.hook = hook
        self.hookConfidence = hookConfidence
        self.scene = scene
        self.sceneConfidence = sceneConfidence
        self.cached = cached
    }
}

/// Actor for generating AI-powered vibe tags via Claude API
public actor VibeGenerator {
    private let httpClient: HTTPClient
    private let logger = Logger(subsystem: "com.cratebot", category: "VibeGenerator")

    public init(httpClient: HTTPClient? = nil) {
        self.httpClient = httpClient ?? HTTPClient()
    }

    /// Check if the vibe generation backend is available
    public func isAvailable() async -> Bool {
        // First check if server is running
        guard await httpClient.healthCheck() else {
            logger.debug("Backend health check failed")
            return false
        }

        // Then check if vibe generation is enabled in settings
        do {
            let settings: BackendAPI.SettingsResponse = try await httpClient.get(path: "/api/v1/settings")
            let available = settings.vibeAvailable && settings.anthropicApiKeySet
            logger.debug("Vibe availability: \(available) (vibeAvailable=\(settings.vibeAvailable), apiKeySet=\(settings.anthropicApiKeySet))")
            return available
        } catch {
            logger.error("Failed to check settings: \(error.localizedDescription)")
            return false
        }
    }

    /// Generate a vibe tag for an audio file
    /// - Parameters:
    ///   - fileURL: URL of the audio file
    ///   - includeHook: Whether to include hook detection (default: true)
    /// - Returns: The generated vibe result
    public func generateVibe(
        for fileURL: URL,
        includeHook: Bool = true
    ) async throws -> VibeResult {
        logger.info("Generating vibe for: \(fileURL.lastPathComponent)")

        // Validate that this is a file URL
        guard fileURL.isFileURL else {
            throw VibeError.invalidFile("URL is not a file URL: \(fileURL)")
        }

        // Validate that the file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VibeError.invalidFile("File does not exist: \(fileURL.path)")
        }

        // Check if backend is available
        guard await httpClient.healthCheck() else {
            throw VibeError.backendUnavailable
        }

        // Build the request
        let request = BackendAPI.VibeRequest(
            filePath: fileURL.path,
            overwrite: false,
            dryRun: false,
            skipHook: !includeHook
        )

        // Make the API call
        let response: BackendAPI.VibeResponse
        do {
            response = try await httpClient.post(path: "/api/v1/vibe/file", body: request)
        } catch let error as HTTPError {
            switch error {
            case .serverNotRunning:
                throw VibeError.backendUnavailable
            case .requestFailed(let statusCode, let message):
                if statusCode == 503 && message.contains("API key") {
                    throw VibeError.apiKeyNotConfigured
                }
                throw VibeError.generationFailed(message)
            default:
                throw VibeError.generationFailed(error.localizedDescription)
            }
        }

        // Check for errors in the response
        if response.status == "failed" {
            if let errorMessage = response.error {
                if errorMessage.contains("API key") || errorMessage.contains("anthropic") {
                    throw VibeError.apiKeyNotConfigured
                }
                throw VibeError.generationFailed(errorMessage)
            }
            throw VibeError.generationFailed("Unknown error")
        }

        // Extract the vibe
        guard let vibe = response.vibe else {
            throw VibeError.generationFailed("No vibe generated")
        }

        logger.info("Generated vibe: \(vibe)")

        return VibeResult(
            vibe: vibe,
            description: response.description,
            hook: response.hook,
            hookConfidence: nil, // Not returned by single-file endpoint
            scene: response.scene,
            sceneConfidence: response.sceneConfidence,
            cached: response.status == "skipped" // Skipped means it was cached
        )
    }

    /// Set the Anthropic API key
    /// - Parameter key: The API key to set
    public func setAPIKey(_ key: String) async throws {
        logger.info("Setting Anthropic API key")

        let request = BackendAPI.APIKeyRequest(apiKey: key)

        do {
            let _: BackendAPI.APIKeyResponse = try await httpClient.post(
                path: "/api/v1/settings/api-key",
                body: request
            )
            logger.info("API key set successfully")
        } catch let error as HTTPError {
            switch error {
            case .serverNotRunning:
                throw VibeError.backendUnavailable
            default:
                throw VibeError.apiKeyFailed(error.localizedDescription)
            }
        }
    }
}
