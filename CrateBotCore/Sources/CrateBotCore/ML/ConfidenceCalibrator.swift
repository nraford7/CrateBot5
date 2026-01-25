import Foundation

/// Calibrates classifier confidence scores using temperature scaling
public struct ConfidenceCalibrator: Codable, Sendable {

    /// Temperature for Platt scaling (learned from validation set)
    public var temperature: Float = 1.0

    /// Label smoothing factor used during training
    public var smoothingFactor: Float = 0.1

    public init(temperature: Float = 1.0, smoothingFactor: Float = 0.1) {
        self.temperature = temperature
        self.smoothingFactor = smoothingFactor
    }

    /// Calibrate a raw confidence score
    public func calibrate(_ rawConfidence: Float) -> Float {
        // Apply temperature scaling
        let scaled = rawConfidence / temperature

        // Apply sigmoid to get calibrated probability
        let calibrated = 1.0 / (1.0 + exp(-scaled))

        // Adjust for label smoothing (reduce overconfidence)
        let adjusted = calibrated * (1.0 - smoothingFactor) + smoothingFactor / 2.0

        return adjusted
    }

    /// Learn optimal temperature from validation predictions
    public mutating func fit(
        predictions: [Float],  // Raw confidences
        labels: [Bool]         // True labels
    ) {
        guard predictions.count == labels.count, !predictions.isEmpty else { return }

        // Simple grid search for optimal temperature
        var bestTemp: Float = 1.0
        var bestLoss: Float = .infinity

        for t in stride(from: 0.5, through: 3.0, by: 0.1) {
            let temp = Float(t)
            var loss: Float = 0

            for (pred, label) in zip(predictions, labels) {
                let scaled = pred / temp
                let calibrated = 1.0 / (1.0 + exp(-scaled))
                let target: Float = label ? 1.0 : 0.0

                // Cross-entropy loss
                loss -= target * log(calibrated + 1e-8) + (1 - target) * log(1 - calibrated + 1e-8)
            }

            if loss < bestLoss {
                bestLoss = loss
                bestTemp = temp
            }
        }

        self.temperature = bestTemp
    }
}
