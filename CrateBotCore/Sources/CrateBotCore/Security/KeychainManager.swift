import Foundation
import Security
import os.log

/// Storage for the Anthropic API key.
///
/// Previously used the macOS keychain, which prompted for the login password
/// on every Debug rebuild because the new binary's code signature didn't match
/// the ACL of the previously-saved entry. The keychain was buying no real
/// security on a single-user Mac — anyone with the account can read either
/// store — so the key now lives in UserDefaults. Persists across rebuilds
/// silently.
public final class KeychainManager: Sendable {
    public static let shared = KeychainManager()

    private let logger = Logger(subsystem: "com.cratebot", category: "KeychainManager")
    private let defaultsKeyPrefix = "com.cratebot.credentials."
    private let legacyKeychainService = "com.cratebot.credentials"

    public enum Key: String, Sendable {
        case anthropicAPIKey = "anthropic_api_key"
    }

    private init() {}

    public func save(_ value: String, for key: Key) throws {
        let normalized = normalizeCredential(value)
        guard !normalized.isEmpty else {
            throw KeychainError.emptyCredential
        }

        UserDefaults.standard.set(normalized, forKey: defaultsKeyPrefix + key.rawValue)
        logger.info("Saved \(key.rawValue) to UserDefaults")
    }

    public func retrieve(key: Key) -> String? {
        if let stored = UserDefaults.standard.string(forKey: defaultsKeyPrefix + key.rawValue) {
            let normalized = normalizeCredential(stored)
            guard !normalized.isEmpty else {
                UserDefaults.standard.removeObject(forKey: defaultsKeyPrefix + key.rawValue)
                logger.warning("Removed empty \(key.rawValue) from UserDefaults")
                return retrieveMigratedLegacyValue(for: key)
            }
            return normalized
        }

        return retrieveMigratedLegacyValue(for: key)
    }

    private func retrieveMigratedLegacyValue(for key: Key) -> String? {
        guard let migrated = retrieveLegacyKeychainValue(for: key) else {
            return nil
        }

        UserDefaults.standard.set(migrated, forKey: defaultsKeyPrefix + key.rawValue)
        logger.info("Migrated \(key.rawValue) from legacy Keychain storage")
        return migrated
    }

    public func delete(key: Key) throws {
        UserDefaults.standard.removeObject(forKey: defaultsKeyPrefix + key.rawValue)
    }

    public func exists(key: Key) -> Bool {
        retrieve(key: key) != nil
    }

    private func retrieveLegacyKeychainValue(for key: Key) -> String? {
        if let value = retrieveLegacyKeychainValue(for: key, usesDataProtectionKeychain: true) {
            return value
        }
        return retrieveLegacyKeychainValue(for: key, usesDataProtectionKeychain: false)
    }

    private func retrieveLegacyKeychainValue(
        for key: Key,
        usesDataProtectionKeychain: Bool
    ) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        let normalized = normalizeCredential(string)
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizeCredential(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case emptyCredential
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode credential"
        case .emptyCredential:
            return "API key cannot be empty"
        case .saveFailed(let status):
            return "Failed to save credential (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete credential (status: \(status))"
        }
    }
}
