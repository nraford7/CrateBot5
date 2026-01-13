import Foundation
import os.log

/// Errors that can occur during HTTP operations
public enum HTTPError: Error, LocalizedError, Sendable {
    case invalidURL
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(String)
    case networkError(String)
    case serverNotRunning

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed(let statusCode, let message):
            return "Request failed with status \(statusCode): \(message)"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverNotRunning:
            return "Backend server is not running"
        }
    }
}

/// Thread-safe HTTP client for backend communication
public actor HTTPClient {
    /// Default base URL for the CrateBot backend
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:8742")!

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.cratebot", category: "HTTPClient")

    public init(baseURL: URL = HTTPClient.defaultBaseURL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Check if the backend server is running and healthy
    public func healthCheck() async -> Bool {
        do {
            let _: BackendAPI.HealthResponse = try await get(path: "/api/v1/health")
            return true
        } catch {
            logger.debug("Health check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Perform a GET request
    public func get<R: Decodable>(path: String) async throws -> R {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw HTTPError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await perform(request: request)
    }

    /// Perform a POST request with a JSON body
    public func post<T: Encodable, R: Decodable>(path: String, body: T) async throws -> R {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw HTTPError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw HTTPError.networkError(error.localizedDescription)
        }

        return try await perform(request: request)
    }

    /// Perform the actual HTTP request
    private func perform<R: Decodable>(request: URLRequest) async throws -> R {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as NSError {
            // Check for connection refused error (server not running)
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCannotConnectToHost {
                throw HTTPError.serverNotRunning
            }
            throw HTTPError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPError.networkError("Invalid response type")
        }

        logger.debug("HTTP \(httpResponse.statusCode) for \(request.url?.path ?? "unknown")")

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HTTPError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            logger.error("Decoding failed: \(error.localizedDescription)")
            throw HTTPError.decodingFailed(error.localizedDescription)
        }
    }
}
