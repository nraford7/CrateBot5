import Foundation

/// The Stage 2 (judgment layer) input feature vector.
///
/// Flattens Stage 1 outputs plus track metadata into a fixed columnar layout:
/// `bin_<tag>` columns (sorted), then `grp_<group>_<class>` columns (sorted),
/// then `bpm` (sentinel `-1.0` when unknown), then `duration`.
///
/// The sorted column order IS the Stage 2 schema — training and inference
/// must produce identical columns. `columnNames` is encoded into Stage 2
/// model metadata so a schema mismatch is detectable at load.
public struct JudgmentFeatureVector {

    /// Sentinel value used for `bpm` when the track's BPM is unknown.
    public static let missingBPMSentinel: Float = -1.0

    /// Column names in deterministic sorted order (the Stage 2 schema).
    public let columnNames: [String]

    /// Feature values, aligned one-to-one with `columnNames`.
    public let values: [Float]

    public init(binaryConfidences: [String: Float],
                groupProbabilities: [String: [String: Float]],
                bpm: Float?,
                durationSeconds: Float) {
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
        vals.append(bpm ?? Self.missingBPMSentinel)

        names.append("duration")
        vals.append(durationSeconds)

        self.columnNames = names
        self.values = vals
    }
}
