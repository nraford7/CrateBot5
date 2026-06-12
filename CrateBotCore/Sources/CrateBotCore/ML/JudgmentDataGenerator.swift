import Foundation

/// Abstraction over the Stage 1 (perception) models for Stage 2 row generation.
///
/// The production implementation wraps the loaded `TagClassifier`s and
/// `MultiClassClassifier`s (wired in the two-phase TrainingCoordinator);
/// unit tests inject a mock so no CoreML model is required.
public protocol Stage1Predictor: Sendable {
    /// Run Stage 1 over one track's cached feature vector.
    /// - Returns: per-tag binary confidences and per-group multi-class probabilities.
    func confidences(
        features: [Float]
    ) async throws -> (binary: [String: Float], groups: [String: [String: Float]])
}

/// One Stage 2 training row: the judgment feature vector, the track's
/// judgment-stage labels (its Timing tags), and the source track ID.
public typealias JudgmentRow = (
    features: JudgmentFeatureVector,
    labels: Set<String>,
    trackID: String
)

/// Builds Stage 2 (judgment layer) training rows from Stage 1 outputs.
///
/// For each track with cached features and at least one tag in a
/// judgment-stage category (Timing), the generator runs the Stage 1
/// predictor and flattens the result — plus BPM and duration — into a
/// `JudgmentFeatureVector` row labeled with the track's Timing tags.
///
/// Category-complete rule (shared with `BinaryTrainingDataGenerator`):
/// a track with NO Timing tags was never assessed for Timing, so it is
/// unknown — not a negative — and produces no row. Tracks without cached
/// feature vectors are skipped and counted.
///
/// BPM/duration sourcing: injected as closures keyed by track ID (= file
/// path) so unit tests stay free of ID3 and file access. Production
/// lookups, wired in the Phase B coordinator: BPM from the ID3 TBPM frame
/// (`ID3Manager.readTags`, `ExtractedTags.bpm`); duration from an
/// `AVAudioFile` header read (`length / processingFormat.sampleRate`) at
/// generation time — a per-file metadata read, chosen over adding a
/// duration field to `EmbeddingCache.CacheEntry` because the cache route
/// would touch every extraction call site and only pay off after a full
/// re-extraction. Missing values use the `-1.0` sentinel, applied inside
/// `JudgmentFeatureVector` (`missingValueSentinel`) so the schema type owns
/// all value semantics.
public struct JudgmentDataGenerator: Sendable {
    private let predictor: any Stage1Predictor
    private let bpmLookup: @Sendable (String) async -> Float?
    private let durationLookup: @Sendable (String) async -> Float?
    private let registry: TagStageRegistry

    public init(
        predictor: any Stage1Predictor,
        bpmLookup: @escaping @Sendable (String) async -> Float?,
        durationLookup: @escaping @Sendable (String) async -> Float?,
        registry: TagStageRegistry = TagStageRegistry()
    ) {
        self.predictor = predictor
        self.bpmLookup = bpmLookup
        self.durationLookup = durationLookup
        self.registry = registry
    }

    /// Generate Stage 2 training rows from collected tracks.
    /// - Parameter tracks: tracks with cached feature vectors attached.
    /// - Returns: the training rows, plus the count of tracks skipped for
    ///   missing cached features. Tracks excluded by the category-complete
    ///   rule (no Timing tags) are not rows and not counted as skipped.
    public func generate(
        from tracks: [TaggedTrack]
    ) async throws -> (rows: [JudgmentRow], skipped: Int) {
        let judgmentCategories = registry.categories(in: .judgment).map { $0.lowercased() }
        var rows: [JudgmentRow] = []
        var skipped = 0

        for track in tracks {
            guard let features = track.features, !features.isEmpty else {
                skipped += 1
                continue
            }

            // Case-insensitive category match, mirroring BinaryTrainingDataGenerator.
            let labels = track.tagsByCategory.reduce(into: Set<String>()) { acc, entry in
                if judgmentCategories.contains(entry.key.lowercased()) {
                    acc.formUnion(entry.value)
                }
            }
            // Category-complete rule: no judgment-stage tags → unknown, no row.
            guard !labels.isEmpty else { continue }

            let (binary, groups) = try await predictor.confidences(features: features)
            let bpm = await bpmLookup(track.id)
            let duration = await durationLookup(track.id)
            let vector = JudgmentFeatureVector(
                binaryConfidences: binary,
                groupProbabilities: groups,
                bpm: bpm,
                durationSeconds: duration
            )
            rows.append((features: vector, labels: labels, trackID: track.id))
        }

        return (rows, skipped)
    }
}
