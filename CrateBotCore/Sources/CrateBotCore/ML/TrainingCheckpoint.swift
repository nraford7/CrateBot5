import Foundation
import os.log

/// A checkpoint for resuming training from a previous session.
/// Saves processed tracks with their extracted features so feature extraction
/// can be resumed if interrupted.
public struct TrainingCheckpoint: Codable, Sendable {
    /// The name of the model being trained
    public let modelName: String

    /// When this checkpoint was created
    public let createdAt: Date

    /// Source directories used for this training run
    public let sourceDirectories: [String]

    /// Tracks that have been processed with their features
    public let processedTracks: [CheckpointTrack]

    /// Total tracks discovered at start of training
    public let totalTracksDiscovered: Int

    /// Version of the checkpoint format for future compatibility
    public let checkpointVersion: Int

    /// Hash of track IDs and their tags at checkpoint creation time
    /// Used to detect if tags have been edited since the checkpoint was created
    public let tagHash: String

    /// Feature extraction configuration used for this checkpoint
    /// nil for v1/v2 checkpoints that don't have this field
    public let featureExtractionConfig: FeatureExtractionConfig?

    private enum CodingKeys: String, CodingKey {
        case modelName, createdAt, sourceDirectories, processedTracks
        case totalTracksDiscovered, checkpointVersion, tagHash, featureExtractionConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelName = try container.decode(String.self, forKey: .modelName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceDirectories = try container.decode([String].self, forKey: .sourceDirectories)
        processedTracks = try container.decode([CheckpointTrack].self, forKey: .processedTracks)
        totalTracksDiscovered = try container.decode(Int.self, forKey: .totalTracksDiscovered)
        checkpointVersion = try container.decodeIfPresent(Int.self, forKey: .checkpointVersion) ?? 1
        // For backwards compatibility, use empty string if tagHash is missing (old checkpoints)
        tagHash = try container.decodeIfPresent(String.self, forKey: .tagHash) ?? ""
        // For backwards compatibility, nil if featureExtractionConfig is missing (v1/v2 checkpoints)
        featureExtractionConfig = try container.decodeIfPresent(FeatureExtractionConfig.self, forKey: .featureExtractionConfig)
    }

    /// A serializable representation of a TaggedTrack
    public struct CheckpointTrack: Codable, Sendable {
        public let id: String
        public let tags: [String]
        public let features: [Float]?

        public init(from track: TaggedTrack) {
            self.id = track.id
            self.tags = Array(track.tags)
            self.features = track.features
        }

        public func toTaggedTrack() -> TaggedTrack {
            TaggedTrack(id: id, tags: Set(tags), features: features)
        }
    }

    /// Compute a hash from track IDs and their tags
    /// This allows detection of tag edits between checkpoint saves
    public static func computeTagHash(from tracks: [TaggedTrack]) -> String {
        // Sort tracks by ID for consistent ordering
        let sortedTracks = tracks.sorted { $0.id < $1.id }

        // Build a string representation of all track IDs and their tags
        var hashInput = ""
        for track in sortedTracks {
            let sortedTags = track.tags.sorted().joined(separator: ",")
            hashInput += "\(track.id):\(sortedTags);"
        }

        // Use a simple hash (djb2 algorithm)
        var hash: UInt64 = 5381
        for char in hashInput.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }

        return String(hash, radix: 16)
    }

    public init(
        modelName: String,
        createdAt: Date = Date(),
        sourceDirectories: [URL],
        processedTracks: [TaggedTrack],
        totalTracksDiscovered: Int,
        featureExtractionConfig: FeatureExtractionConfig? = .default
    ) {
        self.modelName = modelName
        self.createdAt = createdAt
        self.sourceDirectories = sourceDirectories.map { $0.path }
        self.processedTracks = processedTracks.map { CheckpointTrack(from: $0) }
        self.totalTracksDiscovered = totalTracksDiscovered
        self.checkpointVersion = 3  // Version 3 includes feature extraction config
        self.tagHash = Self.computeTagHash(from: processedTracks)
        self.featureExtractionConfig = featureExtractionConfig
    }

    /// Get processed tracks as TaggedTrack array
    public func getTaggedTracks() -> [TaggedTrack] {
        processedTracks.map { $0.toTaggedTrack() }
    }

    /// Get set of processed track IDs for quick lookup
    public func getProcessedTrackIDs() -> Set<String> {
        Set(processedTracks.map { $0.id })
    }
}

/// Manager for saving and loading training checkpoints
public final class CheckpointManager: Sendable {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "CheckpointManager")

    /// Checkpoint save interval (number of tracks)
    public static let saveInterval = 50

    public init() {}

    /// Get the checkpoints directory, creating if needed
    public func checkpointsDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CheckpointError.directoryAccessFailed
        }

        let checkpointsDir = appSupport
            .appendingPathComponent("CrateBot")
            .appendingPathComponent("Checkpoints")

        try FileManager.default.createDirectory(
            at: checkpointsDir,
            withIntermediateDirectories: true
        )

        return checkpointsDir
    }

    /// Get the checkpoint file URL for a specific model name
    public func checkpointURL(for modelName: String) throws -> URL {
        let dir = try checkpointsDirectory()
        let safeModelName = modelName.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(safeModelName).checkpoint.json")
    }

    /// Save a checkpoint
    public func save(_ checkpoint: TrainingCheckpoint) throws {
        let url = try checkpointURL(for: checkpoint.modelName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Use compact output for smaller file size
        encoder.outputFormatting = []

        let data = try encoder.encode(checkpoint)
        try data.write(to: url, options: .atomic)

        logger.info("Saved checkpoint for '\(checkpoint.modelName)' with \(checkpoint.processedTracks.count) tracks")
    }

    /// Load a checkpoint for a model name, if one exists
    public func load(modelName: String) -> TrainingCheckpoint? {
        do {
            let url = try checkpointURL(for: modelName)

            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let checkpoint = try decoder.decode(TrainingCheckpoint.self, from: data)
            logger.info("Loaded checkpoint for '\(modelName)' with \(checkpoint.processedTracks.count) tracks")
            return checkpoint
        } catch {
            logger.warning("Failed to load checkpoint for '\(modelName)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Check if a checkpoint exists for a model name
    public func hasCheckpoint(modelName: String) -> Bool {
        do {
            let url = try checkpointURL(for: modelName)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }

    /// Delete checkpoint for a model name
    public func delete(modelName: String) throws {
        let url = try checkpointURL(for: modelName)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            logger.info("Deleted checkpoint for '\(modelName)'")
        }
    }

    /// Check if checkpoint is compatible with current training run
    /// - Parameters:
    ///   - checkpoint: The checkpoint to validate
    ///   - sourceDirectories: Current source directories
    ///   - currentTracks: Current tracks with their tags (for tag hash validation)
    ///   - currentConfig: Current feature extraction config (for config validation)
    /// - Returns: A result indicating compatibility and any incompatibility reason
    public func isCheckpointCompatible(
        _ checkpoint: TrainingCheckpoint,
        sourceDirectories: [URL],
        currentTracks: [TaggedTrack]? = nil,
        currentConfig: FeatureExtractionConfig? = nil
    ) -> CheckpointCompatibility {
        // Check if source directories match
        let currentPaths = Set(sourceDirectories.map { $0.path })
        let checkpointPaths = Set(checkpoint.sourceDirectories)

        guard currentPaths == checkpointPaths else {
            return .incompatible(reason: .sourceDirectoriesMismatch)
        }

        // Check feature extraction config
        if let currentConfig = currentConfig,
           let checkpointConfig = checkpoint.featureExtractionConfig {
            if currentConfig != checkpointConfig {
                return .incompatible(reason: .featureConfigMismatch)
            }
        }

        // If current tracks are provided, validate tag hash
        if let currentTracks = currentTracks {
            // For v1 checkpoints (no tag hash), we can't validate tags
            // Log a warning but allow resuming for backwards compatibility
            if checkpoint.tagHash.isEmpty {
                logger.warning("Checkpoint has no tag hash (v1 format) - cannot validate tags haven't changed")
                return .compatible(warning: "Checkpoint created before tag validation was added. Tags may have changed.")
            }

            // Compute current tag hash for the subset of tracks that are in the checkpoint
            let checkpointTrackIDs = checkpoint.getProcessedTrackIDs()
            let matchingTracks = currentTracks.filter { checkpointTrackIDs.contains($0.id) }

            if !matchingTracks.isEmpty {
                let currentHash = TrainingCheckpoint.computeTagHash(from: matchingTracks)
                let checkpointTracksForHash = checkpoint.getTaggedTracks()

                // Only compare hashes if we have the same tracks
                if matchingTracks.count == checkpointTracksForHash.count {
                    let checkpointHash = TrainingCheckpoint.computeTagHash(from: checkpointTracksForHash)
                    if currentHash != checkpointHash {
                        return .incompatible(reason: .tagsModified)
                    }
                }
            }
        }

        return .compatible(warning: nil)
    }

    /// Legacy compatibility check (deprecated - use version with currentTracks for full validation)
    @available(*, deprecated, message: "Use isCheckpointCompatible(_:sourceDirectories:currentTracks:) for tag validation")
    public func isCheckpointCompatibleLegacy(
        _ checkpoint: TrainingCheckpoint,
        sourceDirectories: [URL]
    ) -> Bool {
        let result = isCheckpointCompatible(checkpoint, sourceDirectories: sourceDirectories, currentTracks: nil)
        return result.isCompatible
    }
}

/// Result of checkpoint compatibility check
public enum CheckpointCompatibility: Sendable {
    case compatible(warning: String?)
    case incompatible(reason: IncompatibilityReason)

    public var isCompatible: Bool {
        switch self {
        case .compatible: return true
        case .incompatible: return false
        }
    }

    public var warning: String? {
        switch self {
        case .compatible(let warning): return warning
        case .incompatible: return nil
        }
    }

    public var reason: IncompatibilityReason? {
        switch self {
        case .compatible: return nil
        case .incompatible(let reason): return reason
        }
    }
}

/// Reasons why a checkpoint might be incompatible
public enum IncompatibilityReason: Sendable, Equatable {
    case sourceDirectoriesMismatch
    case tagsModified
    case featureDimensionMismatch(expected: Int, found: Int)
    case featureConfigMismatch

    public var description: String {
        switch self {
        case .sourceDirectoriesMismatch:
            return "Source directories have changed since checkpoint was created"
        case .tagsModified:
            return "Tags have been modified since checkpoint was created"
        case .featureDimensionMismatch(let expected, let found):
            return "Feature dimension mismatch: expected \(expected), found \(found) in checkpoint"
        case .featureConfigMismatch:
            return "Feature extraction configuration has changed since checkpoint was created"
        }
    }
}

/// Errors that can occur during checkpoint operations
public enum CheckpointError: Error, LocalizedError {
    case directoryAccessFailed
    case saveFailed(reason: String)
    case loadFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .directoryAccessFailed:
            return "Cannot access checkpoints directory"
        case .saveFailed(let reason):
            return "Failed to save checkpoint: \(reason)"
        case .loadFailed(let reason):
            return "Failed to load checkpoint: \(reason)"
        }
    }
}
