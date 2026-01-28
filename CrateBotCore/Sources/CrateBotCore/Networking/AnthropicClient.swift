import Foundation
import os.log

// MARK: - API Types

/// A message in a conversation
public struct Message: Codable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Request body for the Messages API
public struct MessageRequest: Codable, Sendable {
    public let model: String
    public let maxTokens: Int
    public let system: String?
    public let messages: [Message]

    public init(
        model: String,
        maxTokens: Int,
        system: String? = nil,
        messages: [Message]
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
    }
}

/// A content block in a message response
public struct ContentBlock: Codable, Sendable {
    public let type: String
    public let text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

/// Token usage information
public struct Usage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Response from the Messages API
public struct MessageResponse: Codable, Sendable {
    public let id: String
    public let type: String
    public let role: String
    public let content: [ContentBlock]
    public let model: String
    public let stopReason: String?
    public let stopSequence: String?
    public let usage: Usage

    public init(
        id: String,
        type: String,
        role: String,
        content: [ContentBlock],
        model: String,
        stopReason: String?,
        stopSequence: String?,
        usage: Usage
    ) {
        self.id = id
        self.type = type
        self.role = role
        self.content = content
        self.model = model
        self.stopReason = stopReason
        self.stopSequence = stopSequence
        self.usage = usage
    }

    /// Convenience property to extract text from all content blocks
    public var text: String {
        content.compactMap { $0.text }.joined()
    }
}

/// Error detail from the API
public struct ErrorDetail: Codable, Sendable {
    public let type: String
    public let message: String

    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }
}

/// Error response from the API
public struct ErrorResponse: Codable, Sendable {
    public let type: String
    public let error: ErrorDetail

    public init(type: String, error: ErrorDetail) {
        self.type = type
        self.error = error
    }
}

// MARK: - Error Types

/// Errors that can occur during Anthropic API operations
public enum AnthropicError: Error, LocalizedError, Sendable {
    case apiKeyNotConfigured
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case networkError(String)
    case decodingFailed(String)
    case rateLimited(retryAfter: Int)

    public var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Anthropic API key not configured"
        case .invalidResponse:
            return "Invalid response from Anthropic API"
        case .requestFailed(let statusCode, let message):
            return "API request failed (\(statusCode)): \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(retryAfter) seconds"
        }
    }
}

// MARK: - Anthropic Client

/// Thread-safe client for the Anthropic Messages API
public actor AnthropicClient {
    /// The base URL for the Anthropic API
    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    /// The API version to use
    private static let apiVersion = "2023-06-01"

    /// The default model to use
    public static let defaultModel = "claude-sonnet-4-20250514"

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.cratebot", category: "AnthropicClient")

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Check if an API key is configured (nonisolated for synchronous access)
    public nonisolated var hasAPIKey: Bool {
        KeychainManager.shared.exists(key: .anthropicAPIKey)
    }

    /// Send a message request to the API
    public func sendMessage(_ request: MessageRequest) async throws -> MessageResponse {
        guard let apiKey = KeychainManager.shared.retrieve(key: .anthropicAPIKey) else {
            logger.error("API key not configured")
            throw AnthropicError.apiKeyNotConfigured
        }

        var urlRequest = URLRequest(url: Self.apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            logger.error("Failed to encode request: \(error.localizedDescription)")
            throw AnthropicError.networkError("Failed to encode request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw AnthropicError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type")
            throw AnthropicError.invalidResponse
        }

        logger.debug("Anthropic API response: \(httpResponse.statusCode)")

        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "retry-after") ?? "60") ?? 60
            logger.warning("Rate limited, retry after \(retryAfter) seconds")
            throw AnthropicError.rateLimited(retryAfter: retryAfter)
        }

        // Handle errors
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error response
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw AnthropicError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: errorResponse.error.message
                )
            }
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnthropicError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(MessageResponse.self, from: data)
        } catch {
            logger.error("Failed to decode response: \(error.localizedDescription)")
            throw AnthropicError.decodingFailed(error.localizedDescription)
        }
    }

    /// Convenience method for simple completions
    public func complete(
        prompt: String,
        system: String? = nil,
        model: String = AnthropicClient.defaultModel,
        maxTokens: Int = 1024
    ) async throws -> String {
        let request = MessageRequest(
            model: model,
            maxTokens: maxTokens,
            system: system,
            messages: [Message(role: "user", content: prompt)]
        )

        let response = try await sendMessage(request)
        return response.text
    }
}
