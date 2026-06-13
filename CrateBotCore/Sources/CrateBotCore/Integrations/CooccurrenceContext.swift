import Foundation
import os.log

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
    /// `total_tracks` from the stats file (the whole corpus, NOT the matches for this row).
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

    private static let logger = Logger(subsystem: "com.cratebot.core", category: "Cooccurrence")

    /// Decoded shape of `tag_cooccurrence.json`.
    ///
    /// Wire schema uses snake_case (`base_rates`, `total_tracks`); the Swift API
    /// exposes camelCase (`baseRates`, `totalTracks`) via `CodingKeys`.
    public struct Stats: Decodable, Sendable {
        public let baseRates: [String: Double]
        public let conditional: [String: [String: Double]]
        public let totalTracks: Int

        public init(baseRates: [String: Double], conditional: [String: [String: Double]], totalTracks: Int) {
            self.baseRates = baseRates
            self.conditional = conditional
            self.totalTracks = totalTracks
        }

        private enum CodingKeys: String, CodingKey {
            case baseRates = "base_rates"
            case conditional
            case totalTracks = "total_tracks"
        }
    }

    /// Loads the bundled `tag_cooccurrence.json` resource.
    ///
    /// Returns `nil` if the resource is missing or fails to decode — callers should
    /// treat that as "no co-occurrence context available" rather than a fatal error.
    /// A missing resource file is silent (intentional pre-retrain state); a present-but-
    /// undecodable file is logged at `.error` so corrupt data does not vanish into nil.
    public static func loadFromBundle() -> Stats? {
        guard let url = Bundle.module.url(forResource: "tag_cooccurrence", withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            logger.error("tag_cooccurrence.json present at \(url.path, privacy: .public) but unreadable")
            return nil
        }
        do {
            return try JSONDecoder().decode(Stats.self, from: data)
        } catch {
            logger.error("tag_cooccurrence.json failed to decode: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Returns the top-K co-occurring tags for the given timing label, ranked by lift
    /// (`P(tag | timing) / P(tag)`).
    ///
    /// - Parameters:
    ///   - timing: The timing label to look up in `stats.conditional`.
    ///   - stats: Decoded co-occurrence stats.
    ///   - topK: Maximum number of tags to return.
    ///   - minSupport: Minimum `total_tracks` required to produce a context.
    ///   - minLift: Minimum lift required for a tag to qualify.
    /// - Returns: A `CooccurrenceContext`, or `nil` when support is thin, the row is empty,
    ///   or no tag clears the lift threshold.
    ///
    /// Tags present in `conditional` but missing from `base_rates` (or with a zero base
    /// rate) are silently dropped — we cannot compute lift without P(tag), and inventing
    /// a fallback would defeat the lift filter's purpose.
    public static func context(
        timing: String,
        stats: Stats,
        topK: Int = 3,
        minSupport: Int = 3,
        minLift: Double = 1.2
    ) -> CooccurrenceContext? {
        guard stats.totalTracks >= minSupport else { return nil }
        guard let row = stats.conditional[timing], !row.isEmpty else { return nil }
        let scored = row.compactMap { (tag, p) -> (String, Double)? in
            let base = stats.baseRates[tag] ?? 0
            guard base > 0 else { return nil }
            let lift = p / base
            return lift >= minLift ? (tag, lift) : nil
        }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(topK).map { $0.0 }
        guard !top.isEmpty else { return nil }
        return CooccurrenceContext(timingLabel: timing, coOccurringTags: Array(top), support: stats.totalTracks)
    }
}
