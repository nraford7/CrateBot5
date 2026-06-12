import Foundation

/// The Stage 2 (judgment layer) input feature vector.
///
/// Flattens Stage 1 outputs plus track metadata into a fixed columnar layout:
/// `bin_<tag>` columns (sorted), then `grp_<group>_<class>` columns (sorted),
/// then `bpm`, then `duration` (each sentinel `-1.0` when unknown).
///
/// The sorted column order IS the Stage 2 schema — training and inference
/// must produce identical columns. `columnNames` is encoded into Stage 2
/// model metadata so a schema mismatch is detectable at load. ALL value
/// semantics (including missing-value sentinels) live here, so every
/// producer — training row generation and Chunk 4 inference — shares one
/// source of truth.
public struct JudgmentFeatureVector {

    /// Sentinel value used for `bpm` and `duration` when unknown.
    public static let missingValueSentinel: Float = -1.0

    /// Column names in deterministic sorted order (the Stage 2 schema).
    public let columnNames: [String]

    /// Feature values, aligned one-to-one with `columnNames`.
    public let values: [Float]

    public init(binaryConfidences: [String: Float],
                groupProbabilities: [String: [String: Float]],
                bpm: Float?,
                durationSeconds: Float?) {
        var names: [String] = []
        var vals: [Float] = []

        for tag in binaryConfidences.keys.sorted() {
            names.append("bin_\(tag)")
            vals.append(binaryConfidences[tag]!)
        }

        for group in groupProbabilities.keys.sorted() {
            let classes = groupProbabilities[group]!
            for className in classes.keys.sorted() {
                names.append("grp_\(group)_\(className)")
                vals.append(classes[className]!)
            }
        }

        names.append("bpm")
        vals.append(bpm ?? Self.missingValueSentinel)

        names.append("duration")
        vals.append(durationSeconds ?? Self.missingValueSentinel)

        self.columnNames = names
        self.values = vals
    }
}
