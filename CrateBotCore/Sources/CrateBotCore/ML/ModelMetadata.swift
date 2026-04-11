import Foundation

/// Metadata about a trained tag group (multi-class classifier)
/// Note: This is also defined in TrainingCoordinator, but duplicated here for Codable purposes
public struct TagGroupMetadata: Codable, Sendable {
    /// Name of the tag group (e.g., "BassType", "Vibe")
    public let groupName: String

    /// Classes included in this group
    public let classes: [String]

    /// Overall validation accuracy
    public let accuracy: Double

    /// Per-class accuracy breakdown
    public let perClassAccuracy: [String: Double]

    public init(
        groupName: String,
        classes: [String],
        accuracy: Double,
        perClassAccuracy: [String: Double]
    ) {
        self.groupName = groupName
        self.classes = classes
        self.accuracy = accuracy
        self.perClassAccuracy = perClassAccuracy
    }
}

/// Metadata for a trained CoreML model
public struct ModelMetadata: Codable, Sendable {
    public let name: String
    public let version: String
    public let pipelineVersion: String       // Feature pipeline version for compatibility
    public let trainedAt: Date
    public let trainingFileCount: Int
    public let categories: [String]          // Genre, Timing, Mood, Descriptive
    public let tags: [String: [String]]      // Tags per category (binary classifiers)
    public let tagGroups: [TagGroupMetadata] // Multi-class classifier groups
    public let accuracy: Double?             // Validation accuracy if available
    public let featureDimension: Int         // 1280, 1680, or 2192
    public let calibratorTemperature: Float? // Temperature for confidence calibration
    public let descriptiveSubCategories: [String: [String]]? // Sub-category organization for Descriptive tags
    public let tagThresholds: [String: Float]? // Per-tag classification thresholds

    public init(
        name: String,
        version: String,
        pipelineVersion: String,
        trainedAt: Date,
        trainingFileCount: Int,
        categories: [String],
        tags: [String: [String]],
        tagGroups: [TagGroupMetadata] = [],
        accuracy: Double? = nil,
        featureDimension: Int = 1680,
        calibratorTemperature: Float? = nil,
        descriptiveSubCategories: [String: [String]]? = nil,
        tagThresholds: [String: Float]? = nil
    ) {
        self.name = name
        self.version = version
        self.pipelineVersion = pipelineVersion
        self.trainedAt = trainedAt
        self.trainingFileCount = trainingFileCount
        self.categories = categories
        self.tags = tags
        self.tagGroups = tagGroups
        self.accuracy = accuracy
        self.featureDimension = featureDimension
        self.calibratorTemperature = calibratorTemperature
        self.descriptiveSubCategories = descriptiveSubCategories
        self.tagThresholds = tagThresholds
    }

    // Custom decoder to handle old JSON files without featureDimension or tagGroups
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        pipelineVersion = try container.decode(String.self, forKey: .pipelineVersion)
        trainedAt = try container.decode(Date.self, forKey: .trainedAt)
        trainingFileCount = try container.decode(Int.self, forKey: .trainingFileCount)
        categories = try container.decode([String].self, forKey: .categories)
        tags = try container.decode([String: [String]].self, forKey: .tags)
        // Default to empty array for old models that don't have tag groups
        tagGroups = try container.decodeIfPresent([TagGroupMetadata].self, forKey: .tagGroups) ?? []
        accuracy = try container.decodeIfPresent(Double.self, forKey: .accuracy)
        // Default to 1280 for old models that don't have this field
        featureDimension = try container.decodeIfPresent(Int.self, forKey: .featureDimension) ?? 1280
        // Calibrator temperature is optional (may not exist in old models)
        calibratorTemperature = try container.decodeIfPresent(Float.self, forKey: .calibratorTemperature)
        // Descriptive sub-categories are optional (may not exist in old models)
        descriptiveSubCategories = try container.decodeIfPresent([String: [String]].self, forKey: .descriptiveSubCategories)
        tagThresholds = try container.decodeIfPresent([String: Float].self, forKey: .tagThresholds)
    }

    private enum CodingKeys: String, CodingKey {
        case name, version, pipelineVersion, trainedAt, trainingFileCount
        case categories, tags, tagGroups, accuracy, featureDimension
        case calibratorTemperature, descriptiveSubCategories, tagThresholds
    }

    /// Load metadata from JSON sidecar file
    public static func load(from url: URL) throws -> ModelMetadata {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ModelMetadata.self, from: data)
    }

    /// Save metadata to JSON sidecar file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

/// Available model info
public struct AvailableModel: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let url: URL
    public let metadata: ModelMetadata?
    public let isDefault: Bool

    public init(name: String, url: URL, metadata: ModelMetadata?, isDefault: Bool = false) {
        self.name = name
        self.url = url
        self.metadata = metadata
        self.isDefault = isDefault
    }
}
