import Foundation

/// Represents a track with its associated tags
public struct TaggedTrack: Identifiable, Sendable {
    public let id: String
    public let tags: Set<String>
    public let features: [Float]?

    /// Tags grouped by their top-level category ("Genre", "Timing", "Mood", "Descriptive").
    /// Drives category-complete negative filtering: a track with no tags in a category
    /// is "unknown" for that category's tags, not a trusted negative.
    public let tagsByCategory: [String: Set<String>]

    public init(
        id: String,
        tags: Set<String>,
        features: [Float]? = nil,
        tagsByCategory: [String: Set<String>] = [:]
    ) {
        self.id = id
        self.tags = tags
        self.features = features
        self.tagsByCategory = tagsByCategory
    }

    public init(
        id: String,
        tags: [String],
        features: [Float]? = nil,
        tagsByCategory: [String: Set<String>] = [:]
    ) {
        self.id = id
        self.tags = Set(tags)
        self.features = features
        self.tagsByCategory = tagsByCategory
    }
}

/// Result of generating training data for a single tag
public struct TrainingDataResult: Sendable {
    public let positive: [TaggedTrack]
    public let negative: [TaggedTrack]
    /// Unknowns: tracks with no tags in the target tag's category.
    /// They are excluded from negatives because tag absence there means
    /// "never assessed", not "voted no".
    public let excludedCount: Int

    public init(positive: [TaggedTrack], negative: [TaggedTrack], excludedCount: Int) {
        self.positive = positive
        self.negative = negative
        self.excludedCount = excludedCount
    }
}

/// Generates balanced training data for binary classifiers
public struct BinaryTrainingDataGenerator: Sendable {
    /// Minimum positive examples required to train a tag classifier
    public let minPositiveExamples: Int

    /// Maximum negative:positive ratio to prevent class imbalance
    public let maxNegativeRatio: Double

    public init(minPositiveExamples: Int = 50, maxNegativeRatio: Double = 1.5) {
        self.minPositiveExamples = minPositiveExamples
        self.maxNegativeRatio = maxNegativeRatio
    }

    /// Generate balanced positive/negative training sets for a specific tag,
    /// applying the category-complete rule when a category is given:
    /// only tracks with at least one tag in the target tag's top-level category
    /// are eligible negatives. Tracks with no tags in that category are excluded
    /// as unknown (absence = never assessed, not "voted no").
    ///
    /// - Parameters:
    ///   - tagName: The tag to build a training set for.
    ///   - category: The tag's top-level category (e.g. "Timing"). Pass nil to
    ///     treat every non-positive track as a negative (legacy behavior).
    ///   - tracks: Candidate tracks.
    /// - Returns: The training data, or nil when positives are insufficient or
    ///   no trusted negatives remain.
    public func generateTrainingData(
        for tagName: String,
        category: String?,
        from tracks: [TaggedTrack]
    ) -> TrainingDataResult? {
        let positive = tracks.filter { $0.tags.contains(tagName) }
        let eligible: [TaggedTrack]
        let excluded: Int
        if let category = category {
            // Case-insensitive category key match so "timing" and "Timing" behave identically
            let categoryKey = category.lowercased()
            let hasCategoryTags: (TaggedTrack) -> Bool = { track in
                track.tagsByCategory.contains { $0.key.lowercased() == categoryKey && !$0.value.isEmpty }
            }
            let considered = tracks.filter(hasCategoryTags)
            eligible = considered.filter { !$0.tags.contains(tagName) }
            // Excluded counts only non-positive unknowns: positives are always
            // used, so a positive lacking category tags is not "excluded".
            excluded = tracks.filter { !$0.tags.contains(tagName) && !hasCategoryTags($0) }.count
        } else {
            eligible = tracks.filter { !$0.tags.contains(tagName) }
            excluded = 0
        }

        // Skip tags with insufficient positive data, and tags with no trusted
        // negatives (can't train a binary classifier with a single class)
        guard positive.count >= minPositiveExamples, !eligible.isEmpty else {
            return nil
        }

        // Balance negative samples to avoid overwhelming positives
        let maxNegatives = Int(Double(positive.count) * maxNegativeRatio)
        return TrainingDataResult(
            positive: positive,
            negative: Array(eligible.shuffled().prefix(maxNegatives)),
            excludedCount: excluded
        )
    }

    /// Generate balanced positive/negative training sets for a specific tag
    @available(*, deprecated, message: "Use generateTrainingData(for:category:from:) for category-complete negative filtering")
    public func generateTrainingData(
        for tagName: String,
        from tracks: [TaggedTrack]
    ) -> (positive: [TaggedTrack], negative: [TaggedTrack])? {
        guard let result = generateTrainingData(for: tagName, category: nil, from: tracks) else {
            return nil
        }
        return (result.positive, result.negative)
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
