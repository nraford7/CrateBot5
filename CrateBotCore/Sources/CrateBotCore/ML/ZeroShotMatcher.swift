import Accelerate
import Foundation
import os.log

/// Matches audio embeddings against text embeddings using cosine similarity
/// for zero-shot tag classification via CLAP-style cross-modal matching.
public struct ZeroShotMatcher: Sendable {

    /// A single match result pairing a tag name with its similarity score.
    public struct Match: Sendable, Equatable {
        public let tag: String
        public let similarity: Float
    }

    /// Text embeddings keyed by tag name.
    private let tagEmbeddings: [String: [Float]]
    private let logger = Logger(subsystem: "com.cratebot.core", category: "ZeroShotMatcher")

    /// Creates a matcher from a pre-computed dictionary of tag text embeddings.
    public init(tagEmbeddings: [String: [Float]]) {
        self.tagEmbeddings = tagEmbeddings
    }

    /// Attempts to load tag text embeddings from `clap_tag_embeddings.json` in the bundle.
    /// Returns nil if the file doesn't exist or can't be decoded.
    public static func loadFromBundle() -> ZeroShotMatcher? {
        guard let url = Bundle.module.url(forResource: "clap_tag_embeddings", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let embeddings = try JSONDecoder().decode([String: [Float]].self, from: data)
            return ZeroShotMatcher(tagEmbeddings: embeddings)
        } catch {
            return nil
        }
    }

    /// Matches an audio embedding against all text embeddings, returning tags above `threshold`.
    ///
    /// - Parameters:
    ///   - audioEmbedding: The CLAP audio embedding vector.
    ///   - threshold: Minimum cosine similarity to include (default 0.2).
    ///   - maxResults: Maximum number of matches to return (default 5).
    ///   - excludingTags: Tags to skip (e.g. those already covered by trained classifiers).
    /// - Returns: Matches sorted by descending similarity.
    public func match(
        audioEmbedding: [Float],
        threshold: Float = 0.2,
        maxResults: Int = 5,
        excludingTags: Set<String> = []
    ) -> [Match] {
        var results: [Match] = []

        for (tag, textEmbedding) in tagEmbeddings {
            if excludingTags.contains(tag) { continue }
            let similarity = Self.cosineSimilarity(audioEmbedding, textEmbedding)
            if similarity >= threshold {
                results.append(Match(tag: tag, similarity: similarity))
            }
        }

        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(maxResults))
    }

    // MARK: - Cosine Similarity (Accelerate)

    /// Computes cosine similarity between two vectors using vDSP.
    /// Returns 0 if either vector has zero magnitude.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let count = vDSP_Length(min(a.count, b.count))
        guard count > 0 else { return 0 }

        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0

        a.withUnsafeBufferPointer { aPtr in
            b.withUnsafeBufferPointer { bPtr in
                vDSP_dotpr(aPtr.baseAddress!, 1,
                           bPtr.baseAddress!, 1,
                           &dot, count)
                vDSP_dotpr(aPtr.baseAddress!, 1,
                           aPtr.baseAddress!, 1,
                           &magA, count)
                vDSP_dotpr(bPtr.baseAddress!, 1,
                           bPtr.baseAddress!, 1,
                           &magB, count)
            }
        }

        let denominator = sqrtf(magA) * sqrtf(magB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
}
