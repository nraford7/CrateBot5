import Foundation

/// Preset sample sizes for quick experimentation
public enum SampleSize: String, CaseIterable, Sendable, Codable {
    case quick = "Quick (25)"
    case small = "Small (50)"
    case balanced = "Balanced (100)"
    case large = "Large (250)"
    case full = "Full Library"

    public var count: Int? {
        switch self {
        case .quick: return 25
        case .small: return 50
        case .balanced: return 100
        case .large: return 250
        case .full: return nil
        }
    }

    public var estimatedTime: String {
        switch self {
        case .quick: return "~1-2 min"
        case .small: return "~2-5 min"
        case .balanced: return "~5-10 min"
        case .large: return "~10-20 min"
        case .full: return "~30-60 min"
        }
    }
}

/// Stratified sampling that preserves tag distribution
public struct StratifiedSampler: Sendable {
    private let seed: UInt64

    public init(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.seed = seed
    }

    /// Sample tracks while preserving the distribution of a given property
    /// - Parameters:
    ///   - tracks: All available tracks
    ///   - size: Desired sample size
    ///   - stratifyBy: Key path to property used for stratification
    /// - Returns: Stratified sample of tracks
    public func sample<T: Hashable>(
        from tracks: [TaggedTrack],
        size: SampleSize,
        stratifyBy keyPath: KeyPath<TaggedTrack, T>
    ) -> [TaggedTrack] {
        // Full sample returns everything
        guard let targetCount = size.count else {
            return tracks
        }

        // If we have fewer tracks than requested, return all
        guard tracks.count > targetCount else {
            return tracks
        }

        // Group tracks by stratification key
        var groups: [T: [TaggedTrack]] = [:]
        for track in tracks {
            let key = track[keyPath: keyPath]
            groups[key, default: []].append(track)
        }

        // Calculate how many to sample from each group
        var result: [TaggedTrack] = []
        var rng = SeededRandomNumberGenerator(seed: seed)

        for (_, groupTracks) in groups {
            // Proportional sampling
            let proportion = Double(groupTracks.count) / Double(tracks.count)
            let groupSampleSize = max(1, Int(round(proportion * Double(targetCount))))

            // Shuffle and take
            let shuffled = groupTracks.shuffled(using: &rng)
            let sampled = shuffled.prefix(groupSampleSize)
            result.append(contentsOf: sampled)
        }

        // Adjust to exact target count
        if result.count > targetCount {
            result = Array(result.shuffled(using: &rng).prefix(targetCount))
        }

        return result
    }
}
