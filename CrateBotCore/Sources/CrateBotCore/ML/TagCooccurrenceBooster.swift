import Foundation
import os.log

/// Post-hoc boosting of binary classifier outputs using tag co-occurrence statistics.
///
/// Binary classifiers predict each tag independently, throwing away information about
/// which tags tend to appear together. This booster corrects for that by adjusting
/// each tag's probability based on confident predictions of correlated tags.
///
/// For each tag A with raw probability P(A), and for each "confident" tag B
/// (raw probability ≥ `confidentThreshold`), we adjust P(A) in logit space
/// proportional to the log-lift log(P(A|B) / P(A)). Positive lifts boost, negative
/// lifts penalize. The total adjustment is weighted by `boostWeight`.
public struct TagCooccurrenceBooster: Sendable {

    /// Co-occurrence statistics loaded from bundled JSON.
    public struct Stats: Codable, Sendable {
        public let totalTracks: Int
        public let baseRates: [String: Float]
        public let conditional: [String: [String: Float]]

        private enum CodingKeys: String, CodingKey {
            case totalTracks = "total_tracks"
            case baseRates = "base_rates"
            case conditional
        }

        public init(totalTracks: Int, baseRates: [String: Float], conditional: [String: [String: Float]]) {
            self.totalTracks = totalTracks
            self.baseRates = baseRates
            self.conditional = conditional
        }
    }

    private let stats: Stats
    private let boostWeight: Float
    private let confidentThreshold: Float
    private let logger = Logger(subsystem: "com.cratebot", category: "TagCooccurrenceBooster")

    /// - Parameters:
    ///   - stats: Co-occurrence statistics.
    ///   - boostWeight: How much weight to give the co-occurrence signal vs raw classifier.
    ///     0.0 = no boosting (identity), 1.0 = full Bayes-style adjustment. Default 0.5.
    ///   - confidentThreshold: A tag is treated as a boosting signal only when its raw
    ///     probability meets this threshold. Default 0.8.
    public init(stats: Stats, boostWeight: Float = 0.5, confidentThreshold: Float = 0.8) {
        self.stats = stats
        self.boostWeight = boostWeight
        self.confidentThreshold = confidentThreshold
    }

    /// Load from bundled `tag_cooccurrence.json` resource.
    public static func loadFromBundle(
        boostWeight: Float = 0.5,
        confidentThreshold: Float = 0.8
    ) -> TagCooccurrenceBooster? {
        guard let url = Bundle.module.url(forResource: "tag_cooccurrence", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode(Stats.self, from: data) else {
            return nil
        }
        return TagCooccurrenceBooster(
            stats: stats,
            boostWeight: boostWeight,
            confidentThreshold: confidentThreshold
        )
    }

    /// Adjust raw tag probabilities using co-occurrence statistics.
    ///
    /// The adjustment happens in logit space:
    ///   adjusted_logit(A) = logit(A) + boostWeight · Σ_B log(P(A|B) / P(A))
    /// where the sum is over confident tags B != A that have a conditional probability stored.
    ///
    /// - Parameter probabilities: Raw probabilities per tag from the binary classifiers.
    /// - Returns: Adjusted probabilities, same keys.
    public func adjust(probabilities: [String: Float]) -> [String: Float] {
        // Identify confident tags
        let confidentTags = probabilities.filter { $0.value >= confidentThreshold }.map { $0.key }
        guard !confidentTags.isEmpty else { return probabilities }

        var adjusted: [String: Float] = [:]
        for (tag, p) in probabilities {
            // Don't boost a tag based on its own confidence
            var logLiftSum: Float = 0
            for confidentTag in confidentTags where confidentTag != tag {
                // Look up P(tag | confidentTag)
                if let pBGivenA = stats.conditional[confidentTag]?[tag],
                   let pB = stats.baseRates[tag], pB > 0 {
                    let lift = pBGivenA / pB
                    if lift > 0 {
                        logLiftSum += Float(log(Double(lift)))
                    }
                }
            }

            if logLiftSum == 0 {
                adjusted[tag] = p
            } else {
                let logitP = Self.logit(clamp(p))
                let adjustedLogit = logitP + boostWeight * logLiftSum
                adjusted[tag] = Self.sigmoid(adjustedLogit)
            }
        }

        return adjusted
    }

    // MARK: - Math helpers

    private static let epsilon: Float = 1e-6

    private func clamp(_ p: Float) -> Float {
        return max(Self.epsilon, min(1 - Self.epsilon, p))
    }

    private static func logit(_ p: Float) -> Float {
        return log(p / (1 - p))
    }

    private static func sigmoid(_ x: Float) -> Float {
        return 1 / (1 + exp(-x))
    }
}
