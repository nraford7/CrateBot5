import Foundation
import Security
import os.log

/// Secure storage for sensitive credentials using macOS Keychain
public final class KeychainManager: Sendable {
    public static let shared = KeychainManager()

    private let logger = Logger(subsystem: "com.cratebot", category: "KeychainManager")

    // Keychain service identifier
    private let service = "com.cratebot.credentials"

    // Known key names
    public enum Key: String, Sendable {
        case anthropicAPIKey = "anthropic_api_key"
    }

    private init() {}

    /// Save a string value to the Keychain
    public func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first (if any)
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            logger.error("Failed to save to Keychain: \(status)")
            throw KeychainError.saveFailed(status)
        }

        logger.info("Saved \(key.rawValue) to Keychain")
    }

    /// Retrieve a string value from the Keychain
    public func retrieve(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Delete a value from the Keychain
    public func delete(key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete from Keychain: \(status)")
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if a key exists in the Keychain
    public func exists(key: Key) -> Bool {
        retrieve(key: key) != nil
    }
}

/// Errors that can occur during Keychain operations
public enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for Keychain"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        }
    }
}
