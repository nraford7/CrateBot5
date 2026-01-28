import Foundation
import Accelerate

/// Supervised contrastive loss for better feature separation
public struct ContrastiveLoss: Sendable {

    /// Compute supervised contrastive loss
    /// Pulls same-class embeddings together, pushes different-class apart
    public static func compute(
        embeddings: [[Float]],  // [batch_size, feature_dim]
        labels: [String],
        temperature: Float = 0.07
    ) -> Float {
        let batchSize = embeddings.count
        guard batchSize > 1 else { return 0 }

        // Normalize embeddings
        let normalized = embeddings.map { l2Normalize($0) }

        // Compute similarity matrix
        var similarities = [[Float]](repeating: [Float](repeating: 0, count: batchSize), count: batchSize)
        for i in 0..<batchSize {
            for j in 0..<batchSize {
                similarities[i][j] = dotProduct(normalized[i], normalized[j]) / temperature
            }
        }

        // Compute contrastive loss
        var totalLoss: Float = 0

        for anchor in 0..<batchSize {
            let anchorLabel = labels[anchor]

            // Find positive indices (same class, excluding self)
            var positiveIndices: [Int] = []
            for i in 0..<batchSize where i != anchor && labels[i] == anchorLabel {
                positiveIndices.append(i)
            }

            guard !positiveIndices.isEmpty else { continue }

            // Compute log-sum-exp for denominator (all except self)
            var expSum: Float = 0
            for i in 0..<batchSize where i != anchor {
                expSum += exp(similarities[anchor][i])
            }
            let logDenom = log(expSum + 1e-8)

            // Sum over positives
            var positiveLoss: Float = 0
            for posIdx in positiveIndices {
                positiveLoss += similarities[anchor][posIdx] - logDenom
            }

            totalLoss -= positiveLoss / Float(positiveIndices.count)
        }

        return totalLoss / Float(batchSize)
    }

    /// L2 normalize a vector
    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        let norm = sqrt(sumSquares + 1e-8)

        var normalized = [Float](repeating: 0, count: vector.count)
        var divisor = norm
        vDSP_vsdiv(vector, 1, &divisor, &normalized, 1, vDSP_Length(vector.count))

        return normalized
    }

    /// Dot product of two vectors
    private static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
}
