import Foundation

// MARK: - VibeGenerationInputs

/// Snapshot of everything the vibe generator sees about one track.
///
/// This is the single source of truth for the LLM payload — `promptPayload()`
/// serializes it deterministically (sorted keys, fixed numeric precision) so
/// two identical input sets produce byte-identical prompt strings. The prompt
/// template must not reach in and re-format fields ad hoc; if a field belongs
/// in the prompt, it belongs here.
public struct VibeGenerationInputs: Sendable, Equatable {

    // MARK: Stage 1 outputs

    /// Per-tag binary classifier confidences (post-sigmoid, 0...1).
    public let binaryConfidences: [String: Float]

    /// Per-group multi-class probabilities, e.g. `["BassType": ["Sub Bass": 0.7, ...]]`.
    public let groupProbabilities: [String: [String: Float]]

    /// Structured Stage 1 predictions (thresholded).
    public let predictedTags: UserTagPredictions

    // MARK: Acoustic & metadata

    public let bpm: Float?
    public let key: String?
    public let durationSeconds: Float
    public let title: String?
    public let artist: String?

    // MARK: Stage 2 / cross-tag context

    /// Stage 2 timing argmax + raw confidence (present only when judgment fired).
    public let stage2Timing: TimingPrediction?

    /// Lift-ranked co-occurring tags for the Stage 2 timing label
    /// (present only when there is enough corpus support).
    public let cooccurrence: CooccurrenceContext?

    public init(
        binaryConfidences: [String: Float],
        groupProbabilities: [String: [String: Float]],
        predictedTags: UserTagPredictions,
        bpm: Float?,
        key: String?,
        durationSeconds: Float,
        title: String?,
        artist: String?,
        stage2Timing: TimingPrediction?,
        cooccurrence: CooccurrenceContext?
    ) {
        self.binaryConfidences = binaryConfidences
        self.groupProbabilities = groupProbabilities
        self.predictedTags = predictedTags
        self.bpm = bpm
        self.key = key
        self.durationSeconds = durationSeconds
        self.title = title
        self.artist = artist
        self.stage2Timing = stage2Timing
        self.cooccurrence = cooccurrence
    }

    // MARK: Equatable (UserTagPredictions is not Equatable — compare via projected fields)

    public static func == (lhs: VibeGenerationInputs, rhs: VibeGenerationInputs) -> Bool {
        return lhs.binaryConfidences == rhs.binaryConfidences
            && lhs.groupProbabilities == rhs.groupProbabilities
            && lhs.bpm == rhs.bpm
            && lhs.key == rhs.key
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.stage2Timing == rhs.stage2Timing
            && lhs.cooccurrence == rhs.cooccurrence
            && Self.predictionsEqual(lhs.predictedTags, rhs.predictedTags)
    }

    private static func predictionsEqual(_ a: UserTagPredictions, _ b: UserTagPredictions) -> Bool {
        return a.genre == b.genre
            && a.timing == b.timing
            && a.mood == b.mood
            && a.bassType == b.bassType
            && a.rhythm == b.rhythm
            && a.style == b.style
            && a.vibes == b.vibes
            && a.instruments == b.instruments
            && a.vocalType == b.vocalType
            && a.acapella == b.acapella
            && a.customTags == b.customTags
    }

    // MARK: - Prompt payload

    /// Serializes the inputs to a deterministic JSON string for inclusion in the LLM prompt.
    ///
    /// - Keys are sorted (`JSONEncoder.outputFormatting = .sortedKeys`).
    /// - Float probabilities are rounded to 3 decimal places before encoding, so the
    ///   wire form is stable across machines/runs.
    /// - Optional context blocks (`stage2Timing`, `cooccurrence`) are omitted when nil,
    ///   so the LLM never sees `"null"` placeholders.
    /// - Two calls on the same inputs return byte-identical strings.
    public func promptPayload() -> String {
        // Build an ordered, encodable representation. Since `JSONSerialization` does not
        // guarantee key ordering and we want strict determinism + 3-dp rounding for floats,
        // we hand-encode through a `Codable` shape and let `JSONEncoder.sortedKeys` do the
        // sort.
        let payload = Payload(
            artist: artist,
            binaryConfidences: Self.rounded(binaryConfidences),
            bpm: bpm.map(Self.round3),
            cooccurrence: cooccurrence.map { CooccurrencePayload(
                coOccurringTags: $0.coOccurringTags,
                support: $0.support,
                timingLabel: $0.timingLabel
            ) },
            durationSeconds: Self.round3(durationSeconds),
            groupProbabilities: Self.rounded(groupProbabilities),
            key: key,
            predictedTags: PredictionsPayload(
                acapella: predictedTags.acapella,
                bassType: predictedTags.bassType,
                customTags: predictedTags.customTags,
                genre: predictedTags.genre,
                instruments: predictedTags.instruments,
                mood: predictedTags.mood,
                rhythm: predictedTags.rhythm,
                style: predictedTags.style,
                timing: predictedTags.timing,
                vibes: predictedTags.vibes,
                vocalType: predictedTags.vocalType
            ),
            stage2Timing: stage2Timing.map { TimingPayload(
                confidence: Self.round3($0.confidence),
                label: $0.label
            ) },
            title: title
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Force deterministic Double encoding (no exponent drift).
        encoder.nonConformingFloatEncodingStrategy = .throw
        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            // Unreachable for these field types; return empty object as a safety net.
            return "{}"
        }
        return string
    }

    // MARK: - Rounding helpers

    private static func round3(_ value: Float) -> Float {
        // Round to 3 decimal places by scaling, rounding, descaling.
        let scaled = (value * 1000.0).rounded()
        return scaled / 1000.0
    }

    private static func rounded(_ dict: [String: Float]) -> [String: Float] {
        var out: [String: Float] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict { out[k] = round3(v) }
        return out
    }

    private static func rounded(_ dict: [String: [String: Float]]) -> [String: [String: Float]] {
        var out: [String: [String: Float]] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict { out[k] = rounded(v) }
        return out
    }

    // MARK: - Codable payload shapes
    //
    // These mirror the public fields verbatim. Keeping them private + Encodable
    // means the prompt JSON schema is owned here and cannot drift from the type.

    private struct Payload: Encodable {
        let artist: String?
        let binaryConfidences: [String: Float]
        let bpm: Float?
        let cooccurrence: CooccurrencePayload?
        let durationSeconds: Float
        let groupProbabilities: [String: [String: Float]]
        let key: String?
        let predictedTags: PredictionsPayload
        let stage2Timing: TimingPayload?
        let title: String?
    }

    private struct CooccurrencePayload: Encodable {
        let coOccurringTags: [String]
        let support: Int
        let timingLabel: String
    }

    private struct TimingPayload: Encodable {
        let confidence: Float
        let label: String
    }

    private struct PredictionsPayload: Encodable {
        let acapella: Bool?
        let bassType: String?
        let customTags: [String]
        let genre: String?
        let instruments: [String]
        let mood: String?
        let rhythm: [String]
        let style: [String]
        let timing: String?
        let vibes: [String]
        let vocalType: String?
    }
}
