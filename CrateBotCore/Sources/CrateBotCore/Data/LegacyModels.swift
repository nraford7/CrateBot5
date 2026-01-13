import Foundation

/// Legacy CrateBot3 data formats for migration
public enum LegacyModels {

    /// Legacy config format (~/.cratebot/config.json)
    public struct LegacyConfig: Codable, Sendable {
        public let anthropicApiKey: String?
        public let defaultModel: String?
        public let whisperModel: String?
        public let enablePanns: Bool?
        public let enableEssentia: Bool?
        public let lastUsedFolder: String?
        public let recentFolders: [String]?

        enum CodingKeys: String, CodingKey {
            case anthropicApiKey = "anthropic_api_key"
            case defaultModel = "default_model"
            case whisperModel = "whisper_model"
            case enablePanns = "enable_panns"
            case enableEssentia = "enable_essentia"
            case lastUsedFolder = "last_used_folder"
            case recentFolders = "recent_folders"
        }
    }

    /// Legacy refinement session entry
    public struct LegacyRefinementEntry: Codable, Sendable {
        public let filePath: String
        public let originalTags: [String: String]
        public let correctedTags: [String: String]
        public let timestamp: String

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case originalTags = "original_tags"
            case correctedTags = "corrected_tags"
            case timestamp
        }
    }

    /// Detected legacy data summary
    public struct DetectedLegacyData: Sendable {
        public let hasConfig: Bool
        public let hasModels: Bool
        public let modelCount: Int
        public let hasRefinementSession: Bool
        public let refinementEntryCount: Int
        public let hasCheckpoints: Bool
        public let checkpointCount: Int
        public let hasCache: Bool
        public let cacheFileCount: Int

        public var isEmpty: Bool {
            !hasConfig && !hasModels && !hasRefinementSession && !hasCheckpoints && !hasCache
        }

        public init(
            hasConfig: Bool,
            hasModels: Bool,
            modelCount: Int,
            hasRefinementSession: Bool,
            refinementEntryCount: Int,
            hasCheckpoints: Bool,
            checkpointCount: Int,
            hasCache: Bool,
            cacheFileCount: Int
        ) {
            self.hasConfig = hasConfig
            self.hasModels = hasModels
            self.modelCount = modelCount
            self.hasRefinementSession = hasRefinementSession
            self.refinementEntryCount = refinementEntryCount
            self.hasCheckpoints = hasCheckpoints
            self.checkpointCount = checkpointCount
            self.hasCache = hasCache
            self.cacheFileCount = cacheFileCount
        }
    }
}
