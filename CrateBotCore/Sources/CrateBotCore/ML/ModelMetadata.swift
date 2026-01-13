import Foundation

/// Metadata for a trained CoreML model
public struct ModelMetadata: Codable, Sendable {
    public let name: String
    public let version: String
    public let pipelineVersion: String       // Feature pipeline version for compatibility
    public let trainedAt: Date
    public let trainingFileCount: Int
    public let categories: [String]          // Genre, Timing, Mood, Descriptive
    public let tags: [String: [String]]      // Tags per category
    public let accuracy: Double?             // Validation accuracy if available

    public init(
        name: String,
        version: String,
        pipelineVersion: String,
        trainedAt: Date,
        trainingFileCount: Int,
        categories: [String],
        tags: [String: [String]],
        accuracy: Double? = nil
    ) {
        self.name = name
        self.version = version
        self.pipelineVersion = pipelineVersion
        self.trainedAt = trainedAt
        self.trainingFileCount = trainingFileCount
        self.categories = categories
        self.tags = tags
        self.accuracy = accuracy
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
