import Foundation

/// K-fold cross-validation for model evaluation
public struct CrossValidator: Sendable {
    public let folds: Int
    public let seed: UInt64

    public init(folds: Int = 5, seed: UInt64 = 42) {
        precondition(folds >= 2, "Cross-validation requires at least 2 folds")
        self.folds = folds
        self.seed = seed
    }

    /// A single fold containing train and test splits
    public struct Fold: Sendable {
        public let train: [TaggedTrack]
        public let test: [TaggedTrack]
        public let foldIndex: Int
    }

    /// Create k folds from the given tracks
    public func createFolds(from tracks: [TaggedTrack]) -> [Fold] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        let shuffled = tracks.shuffled(using: &rng)

        let foldSize = shuffled.count / folds
        var foldsList: [Fold] = []

        for i in 0..<folds {
            let testStart = i * foldSize
            let testEnd = (i == folds - 1) ? shuffled.count : (i + 1) * foldSize

            let test = Array(shuffled[testStart..<testEnd])
            var train: [TaggedTrack] = []

            if testStart > 0 {
                train.append(contentsOf: shuffled[0..<testStart])
            }
            if testEnd < shuffled.count {
                train.append(contentsOf: shuffled[testEnd..<shuffled.count])
            }

            foldsList.append(Fold(train: train, test: test, foldIndex: i))
        }

        return foldsList
    }
}

/// Metrics from validation
public struct ValidationMetrics: Codable, Sendable {
    public let accuracy: Double
    public let precision: Double
    public let recall: Double
    public let f1Score: Double
    public let truePositives: Int
    public let falsePositives: Int
    public let trueNegatives: Int
    public let falseNegatives: Int

    public init(
        accuracy: Double,
        precision: Double,
        recall: Double,
        f1Score: Double,
        truePositives: Int,
        falsePositives: Int,
        trueNegatives: Int,
        falseNegatives: Int
    ) {
        self.accuracy = accuracy
        self.precision = precision
        self.recall = recall
        self.f1Score = f1Score
        self.truePositives = truePositives
        self.falsePositives = falsePositives
        self.trueNegatives = trueNegatives
        self.falseNegatives = falseNegatives
    }

    /// Calculate metrics from predictions
    public static func calculate(from predictions: [(predicted: Bool, actual: Bool)]) -> ValidationMetrics {
        var tp = 0, fp = 0, tn = 0, fn = 0

        for (predicted, actual) in predictions {
            switch (predicted, actual) {
            case (true, true): tp += 1
            case (true, false): fp += 1
            case (false, true): fn += 1
            case (false, false): tn += 1
            }
        }

        let total = Double(tp + fp + tn + fn)
        let accuracy = total > 0 ? Double(tp + tn) / total : 0
        let precision = (tp + fp) > 0 ? Double(tp) / Double(tp + fp) : 0
        let recall = (tp + fn) > 0 ? Double(tp) / Double(tp + fn) : 0
        let f1 = (precision + recall) > 0 ? 2 * precision * recall / (precision + recall) : 0

        return ValidationMetrics(
            accuracy: accuracy,
            precision: precision,
            recall: recall,
            f1Score: f1,
            truePositives: tp,
            falsePositives: fp,
            trueNegatives: tn,
            falseNegatives: fn
        )
    }

    /// Combine metrics across multiple folds
    /// - Note: Rate metrics (accuracy, precision, recall, F1) are averaged.
    ///         Count metrics (TP, FP, TN, FN) are summed to get totals.
    public static func average(_ metrics: [ValidationMetrics]) -> ValidationMetrics {
        guard !metrics.isEmpty else {
            return ValidationMetrics(
                accuracy: 0, precision: 0, recall: 0, f1Score: 0,
                truePositives: 0, falsePositives: 0, trueNegatives: 0, falseNegatives: 0
            )
        }

        let count = Double(metrics.count)
        return ValidationMetrics(
            accuracy: metrics.map(\.accuracy).reduce(0, +) / count,
            precision: metrics.map(\.precision).reduce(0, +) / count,
            recall: metrics.map(\.recall).reduce(0, +) / count,
            f1Score: metrics.map(\.f1Score).reduce(0, +) / count,
            truePositives: metrics.map(\.truePositives).reduce(0, +),
            falsePositives: metrics.map(\.falsePositives).reduce(0, +),
            trueNegatives: metrics.map(\.trueNegatives).reduce(0, +),
            falseNegatives: metrics.map(\.falseNegatives).reduce(0, +)
        )
    }
}
