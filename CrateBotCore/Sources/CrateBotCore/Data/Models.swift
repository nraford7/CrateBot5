import Foundation
import SwiftData

@Model
public class CachedFeatures {
    @Attribute(.unique) public var audioHash: String
    public var compressedFeatures: Data
    public var pipelineVersion: String
    public var featureCount: Int
    public var extractedAt: Date

    public init(
        audioHash: String,
        compressedFeatures: Data,
        pipelineVersion: String,
        featureCount: Int,
        extractedAt: Date = .now
    ) {
        self.audioHash = audioHash
        self.compressedFeatures = compressedFeatures
        self.pipelineVersion = pipelineVersion
        self.featureCount = featureCount
        self.extractedAt = extractedAt
    }
}

@Model
public class TagOverride {
    @Attribute(.unique) public var audioHash: String
    public var genre: String?
    public var mood: [String]
    public var timing: String?
    public var descriptive: [String]
    public var correctedAt: Date

    public init(
        audioHash: String,
        genre: String? = nil,
        mood: [String] = [],
        timing: String? = nil,
        descriptive: [String] = [],
        correctedAt: Date = .now
    ) {
        self.audioHash = audioHash
        self.genre = genre
        self.mood = mood
        self.timing = timing
        self.descriptive = descriptive
        self.correctedAt = correctedAt
    }
}

// MARK: - Schema Versioning

public enum CrateBotSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [CachedFeatures.self, TagOverride.self]
    }
}

public enum CrateBotMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CrateBotSchemaV1.self]
    }
    public static var stages: [MigrationStage] {
        []
    }
}
