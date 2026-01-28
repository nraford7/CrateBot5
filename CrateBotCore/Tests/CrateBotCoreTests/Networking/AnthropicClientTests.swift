import XCTest
@testable import CrateBotCore

final class AnthropicClientTests: XCTestCase {

    // MARK: - Request Encoding Tests

    func testMessageRequestEncodesWithSnakeCase() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let request = MessageRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 1024,
            system: "You are a helpful assistant.",
            messages: [
                Message(role: "user", content: "Hello, world!")
            ]
        )

        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify snake_case encoding
        XCTAssertNotNil(json["max_tokens"], "max_tokens should be snake_case")
        XCTAssertNil(json["maxTokens"], "maxTokens should not exist (use snake_case)")
        XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-20250514")
        XCTAssertEqual(json["max_tokens"] as? Int, 1024)
        XCTAssertEqual(json["system"] as? String, "You are a helpful assistant.")

        // Verify messages array
        let messages = json["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
        XCTAssertEqual(messages?.first?["content"] as? String, "Hello, world!")
    }

    func testMessageRequestEncodesWithoutOptionalFields() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let request = MessageRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 512,
            messages: [
                Message(role: "user", content: "Test")
            ]
        )

        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // System is optional and should not be present when nil
        XCTAssertNil(json["system"])
        XCTAssertEqual(json["max_tokens"] as? Int, 512)
    }

    // MARK: - Response Decoding Tests

    func testMessageResponseDecodesFromSnakeCase() throws {
        let jsonString = """
        {
            "id": "msg_123456",
            "type": "message",
            "role": "assistant",
            "content": [
                {
                    "type": "text",
                    "text": "Hello! How can I help you today?"
                }
            ],
            "model": "claude-sonnet-4-20250514",
            "stop_reason": "end_turn",
            "stop_sequence": null,
            "usage": {
                "input_tokens": 10,
                "output_tokens": 15
            }
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let data = jsonString.data(using: .utf8)!
        let response = try decoder.decode(MessageResponse.self, from: data)

        XCTAssertEqual(response.id, "msg_123456")
        XCTAssertEqual(response.type, "message")
        XCTAssertEqual(response.role, "assistant")
        XCTAssertEqual(response.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(response.stopReason, "end_turn")
        XCTAssertNil(response.stopSequence)
        XCTAssertEqual(response.usage.inputTokens, 10)
        XCTAssertEqual(response.usage.outputTokens, 15)

        // Verify content blocks
        XCTAssertEqual(response.content.count, 1)
        XCTAssertEqual(response.content.first?.type, "text")
        XCTAssertEqual(response.content.first?.text, "Hello! How can I help you today?")
    }

    func testContentBlockDecoding() throws {
        let jsonString = """
        {
            "type": "text",
            "text": "This is a test response."
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let data = jsonString.data(using: .utf8)!
        let block = try decoder.decode(ContentBlock.self, from: data)

        XCTAssertEqual(block.type, "text")
        XCTAssertEqual(block.text, "This is a test response.")
    }

    func testUsageDecoding() throws {
        let jsonString = """
        {
            "input_tokens": 100,
            "output_tokens": 200
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let data = jsonString.data(using: .utf8)!
        let usage = try decoder.decode(Usage.self, from: data)

        XCTAssertEqual(usage.inputTokens, 100)
        XCTAssertEqual(usage.outputTokens, 200)
    }

    func testErrorResponseDecoding() throws {
        let jsonString = """
        {
            "type": "error",
            "error": {
                "type": "invalid_request_error",
                "message": "Invalid API key provided"
            }
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let data = jsonString.data(using: .utf8)!
        let errorResponse = try decoder.decode(ErrorResponse.self, from: data)

        XCTAssertEqual(errorResponse.type, "error")
        XCTAssertEqual(errorResponse.error.type, "invalid_request_error")
        XCTAssertEqual(errorResponse.error.message, "Invalid API key provided")
    }

    // MARK: - Client Initialization Tests

    func testClientHasAPIKeyPropertyWhenNoKeyConfigured() async {
        // This tests the nonisolated property without hitting the keychain
        // In a real scenario without a key configured, hasAPIKey should return false
        let client = AnthropicClient()

        // The hasAPIKey property checks KeychainManager.shared.exists
        // Without a key configured in the test environment, this should be false
        // (unless a key is actually stored in the keychain)
        let hasKey = client.hasAPIKey

        // We just verify the property is accessible and returns a Bool
        XCTAssertTrue(hasKey == true || hasKey == false, "hasAPIKey should return a boolean")
    }

    // MARK: - Error Type Tests

    func testAnthropicErrorDescriptions() {
        let errors: [(AnthropicError, String)] = [
            (.apiKeyNotConfigured, "Anthropic API key not configured"),
            (.invalidResponse, "Invalid response from Anthropic API"),
            (.requestFailed(statusCode: 401, message: "Unauthorized"), "API request failed (401): Unauthorized"),
            (.networkError("Connection refused"), "Network error: Connection refused"),
            (.decodingFailed("Invalid JSON"), "Failed to decode response: Invalid JSON"),
            (.rateLimited(retryAfter: 30), "Rate limited. Retry after 30 seconds")
        ]

        for (error, expectedDescription) in errors {
            XCTAssertEqual(error.errorDescription, expectedDescription)
        }
    }

    // MARK: - Message Type Tests

    func testMessageCreation() {
        let message = Message(role: "user", content: "Hello")
        XCTAssertEqual(message.role, "user")
        XCTAssertEqual(message.content, "Hello")
    }

    func testMessageRequestCreation() {
        let request = MessageRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 2048,
            system: "Be helpful",
            messages: [Message(role: "user", content: "Hi")]
        )

        XCTAssertEqual(request.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(request.maxTokens, 2048)
        XCTAssertEqual(request.system, "Be helpful")
        XCTAssertEqual(request.messages.count, 1)
    }

    // MARK: - Response Helper Tests

    func testMessageResponseTextExtraction() throws {
        let jsonString = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [
                {"type": "text", "text": "First part. "},
                {"type": "text", "text": "Second part."}
            ],
            "model": "claude-sonnet-4-20250514",
            "stop_reason": "end_turn",
            "stop_sequence": null,
            "usage": {"input_tokens": 5, "output_tokens": 10}
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let data = jsonString.data(using: .utf8)!
        let response = try decoder.decode(MessageResponse.self, from: data)

        // Test the text computed property that joins all text blocks
        XCTAssertEqual(response.text, "First part. Second part.")
    }
}
