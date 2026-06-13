import Foundation

// MARK: - CooccurrenceContext

/// Lift-ranked co-occurring tags for a given timing label, derived from corpus-wide stats.
///
/// Returned by `Cooccurrence.context(...)` when there is enough support to make a non-trivial
/// recommendation. Tags listed in `coOccurringTags` are ordered by descending lift
/// (P(tag | timing) / P(tag)) and are guaranteed to exceed the configured lift threshold,
/// so they reflect a genuine association rather than a base-rate artifact.
public struct CooccurrenceContext: Sendable, Equatable {
    public let timingLabel: String
    /// Top-K co-occurring tags, ordered by descending lift.
    public let coOccurringTags: [String]
    /// Total tracks contributing to the stats this context was derived from.
    public let support: Int

    public init(timingLabel: String, coOccurringTags: [String], support: Int) {
        self.timingLabel = timingLabel
        self.coOccurringTags = coOccurringTags
        self.support = support
    }
}

// MARK: - Cooccurrence

/// Namespace for tag co-occurrence statistics loaded from `tag_cooccurrence.json`.
///
/// The bundled JSON is symmetric pairwise P(other | tag) plus per-tag base rates.
/// Pre-retrain, some timing rows (e.g. `Peak`) may be empty; the extractor returns
/// `nil` in that case rather than inventing a result.
public enum Cooccurrence {

    /// Decoded shape of `tag_cooccurrence.json`.
    public struct Stats: Decodable, Sendable {
        public let base_rates: [String: Double]
        public let conditional: [String: [String: Double]]
        public let total_tracks: Int
    }

    /// Loads the bundled `tag_cooccurrence.json` resource.
    ///
    /// Returns `nil` if the resource is missing or fails to decode — callers should
    /// treat that as "no co-occurrence context available" rather than a fatal error.
    public static func loadFromBundle() -> Stats? {
        guard let url = Bundle.module.url(forResource: "tag_cooccurrence", withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Stats.self, from: data)
    }

    /// Returns the top-K co-occurring tags for the given timing label, ranked by lift
    /// (`P(tag | timing) / P(tag)`).
    ///
    /// - Parameters:
    ///   - forTags: Currently unused (v1); reserved for future filtering against the track's own tags.
    ///   - timing: The timing label to look up in `stats.conditional`.
    ///   - stats: Decoded co-occurrence stats.
    ///   - topK: Maximum number of tags to return.
    ///   - minSupport: Minimum `total_tracks` required to produce a context.
    ///   - minLift: Minimum lift required for a tag to qualify.
    /// - Returns: A `CooccurrenceContext`, or `nil` when support is thin, the row is empty,
    ///   or no tag clears the lift threshold.
    public static func context(
        forTags: Set<String>,
        timing: String,
        stats: Stats,
        topK: Int = 3,
        minSupport: Int = 3,
        minLift: Double = 1.2
    ) -> CooccurrenceContext? {
        guard stats.total_tracks >= minSupport else { return nil }
        guard let row = stats.conditional[timing], !row.isEmpty else { return nil }
        let scored = row.compactMap { (tag, p) -> (String, Double)? in
            let base = stats.base_rates[tag] ?? 0
            guard base > 0 else { return nil }
            let lift = p / base
            return lift >= minLift ? (tag, lift) : nil
        }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(topK).map { $0.0 }
        guard !top.isEmpty else { return nil }
        return CooccurrenceContext(timingLabel: timing, coOccurringTags: Array(top), support: stats.total_tracks)
    }
}
