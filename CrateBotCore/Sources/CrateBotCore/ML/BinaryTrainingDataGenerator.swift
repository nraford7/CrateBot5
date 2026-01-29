import Foundation

/// Represents a track with its associated tags
public struct TaggedTrack: Identifiable, Sendable {
    public let id: String
    public let tags: Set<String>
    public let features: [Float]?

    public init(id: String, tags: Set<String>, features: [Float]? = nil) {
        self.id = id
        self.tags = tags
        self.features = features
    }

    public init(id: String, tags: [String], features: [Float]? = nil) {
        self.id = id
        self.tags = Set(tags)
        self.features = features
    }
}

/// Generates balanced training data for binary classifiers
public struct BinaryTrainingDataGenerator: Sendable {
    /// Minimum positive examples required to train a tag classifier
    public let minPositiveExamples: Int

    /// Maximum negative:positive ratio to prevent class imbalance
    public let maxNegativeRatio: Double

    public init(minPositiveExamples: Int = 50, maxNegativeRatio: Double = 3.0) {
        self.minPositiveExamples = minPositiveExamples
        self.maxNegativeRatio = maxNegativeRatio
    }

    /// Generate balanced positive/negative training sets for a specific tag
    public func generateTrainingData(
        for tagName: String,
        from tracks: [TaggedTrack]
    ) -> (positive: [TaggedTrack], negative: [TaggedTrack])? {
        let positive = tracks.filter { $0.tags.contains(tagName) }
        let negative = tracks.filter { !$0.tags.contains(tagName) }

        // Skip tags with insufficient positive data
        guard positive.count >= minPositiveExamples else {
            return nil
        }

        // Skip tags with no negative samples (can't train binary classifier with single class)
        guard !negative.isEmpty else {
            return nil
        }

        // Balance negative samples to avoid overwhelming positives
        let maxNegatives = Int(Double(positive.count) * maxNegativeRatio)
        let balancedNegative = Array(negative.shuffled().prefix(maxNegatives))

        return (positive, balancedNegative)
    }

    /// Get all viable tags (those with sufficient positive examples)
    public func viableTags(from tracks: [TaggedTrack]) -> [String: Int] {
        var tagCounts: [String: Int] = [:]

        for track in tracks {
            for tag in track.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        return tagCounts.filter { $0.value >= minPositiveExamples }
    }
}
