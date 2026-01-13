import Foundation
import os.log

/// Imports legacy CrateBot3 data
public actor LegacyImporter {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "LegacyImporter")
    private let legacyBasePath: URL
    private let fileManager = FileManager.default

    public init(legacyBasePath: URL? = nil) {
        self.legacyBasePath = legacyBasePath ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cratebot")
    }

    public enum ImportError: Error, LocalizedError, Sendable {
        case noLegacyData
        case backupFailed(String)
        case migrationFailed(String)
        case rollbackFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noLegacyData:
                return "No legacy CrateBot3 data found"
            case .backupFailed(let reason):
                return "Backup failed: \(reason)"
            case .migrationFailed(let reason):
                return "Migration failed: \(reason)"
            case .rollbackFailed(let reason):
                return "Rollback failed: \(reason)"
            }
        }
    }

    /// Detect what legacy data exists
    public func detectLegacyData() -> LegacyModels.DetectedLegacyData {
        let configPath = legacyBasePath.appendingPathComponent("config.json")
        let modelsPath = legacyBasePath.appendingPathComponent("models")
        let refinementPath = legacyBasePath.appendingPathComponent("data/refinement_session.json")
        let checkpointsPath = legacyBasePath.appendingPathComponent("checkpoints")
        let cachePath = legacyBasePath.appendingPathComponent("cache")

        let hasConfig = fileManager.fileExists(atPath: configPath.path)

        var modelCount = 0
        if let files = try? fileManager.contentsOfDirectory(atPath: modelsPath.path) {
            modelCount = files.filter { $0.hasSuffix(".pkl") }.count
        }

        var refinementEntryCount = 0
        if let data = try? Data(contentsOf: refinementPath),
           let entries = try? JSONDecoder().decode([LegacyModels.LegacyRefinementEntry].self, from: data) {
            refinementEntryCount = entries.count
        }

        var checkpointCount = 0
        if let files = try? fileManager.contentsOfDirectory(atPath: checkpointsPath.path) {
            checkpointCount = files.filter { $0.hasSuffix(".json") }.count
        }

        var cacheFileCount = 0
        if let files = try? fileManager.contentsOfDirectory(atPath: cachePath.path) {
            cacheFileCount = files.count
        }

        return LegacyModels.DetectedLegacyData(
            hasConfig: hasConfig,
            hasModels: modelCount > 0,
            modelCount: modelCount,
            hasRefinementSession: refinementEntryCount > 0,
            refinementEntryCount: refinementEntryCount,
            hasCheckpoints: checkpointCount > 0,
            checkpointCount: checkpointCount,
            hasCache: cacheFileCount > 0,
            cacheFileCount: cacheFileCount
        )
    }

    /// Create timestamped backup before migration
    public func createBackup() throws -> URL {
        guard fileManager.fileExists(atPath: legacyBasePath.path) else {
            throw ImportError.noLegacyData
        }

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "cratebot_backup_\(timestamp)"
        let backupPath = legacyBasePath
            .deletingLastPathComponent()
            .appendingPathComponent(backupName)

        do {
            try fileManager.copyItem(at: legacyBasePath, to: backupPath)
            logger.info("Created backup at \(backupPath.path)")
            return backupPath
        } catch {
            throw ImportError.backupFailed(error.localizedDescription)
        }
    }

    /// Import legacy config
    public func importConfig() throws -> LegacyModels.LegacyConfig? {
        let configPath = legacyBasePath.appendingPathComponent("config.json")

        guard fileManager.fileExists(atPath: configPath.path) else {
            return nil
        }

        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(LegacyModels.LegacyConfig.self, from: data)

        // Migrate to UserDefaults
        if let apiKey = config.anthropicApiKey {
            UserDefaults.standard.set(apiKey, forKey: "anthropicAPIKey")
        }
        if let whisperModel = config.whisperModel {
            UserDefaults.standard.set(whisperModel, forKey: "whisperModelSize")
        }

        logger.info("Imported legacy config")
        return config
    }

    /// List available backups
    public func listBackups() -> [URL] {
        let parentDir = legacyBasePath.deletingLastPathComponent()

        guard let contents = try? fileManager.contentsOfDirectory(
            at: parentDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents
            .filter { $0.lastPathComponent.hasPrefix("cratebot_backup_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Restore from backup
    public func restoreBackup(from backupURL: URL) throws {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw ImportError.rollbackFailed("Backup not found")
        }

        do {
            // Remove current data
            if fileManager.fileExists(atPath: legacyBasePath.path) {
                try fileManager.removeItem(at: legacyBasePath)
            }

            // Restore from backup
            try fileManager.copyItem(at: backupURL, to: legacyBasePath)
            logger.info("Restored from backup \(backupURL.lastPathComponent)")
        } catch {
            throw ImportError.rollbackFailed(error.localizedDescription)
        }
    }
}
