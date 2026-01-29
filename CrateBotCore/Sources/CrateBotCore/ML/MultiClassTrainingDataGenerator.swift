import Foundation

public final class MultiClassTrainingDataGenerator: Sendable {

    public struct ClassifiedSample: Sendable {
        public let trackId: String
        public let className: String
        public let features: [Float]
    }

    public struct MultiClassTrainingData: Sendable {
        public let groupName: String
        public let classes: [String]
        public let samples: [ClassifiedSample]

        public var classCounts: [String: Int] {
            var counts: [String: Int] = [:]
            for sample in samples {
                counts[sample.className, default: 0] += 1
            }
            return counts
        }
    }

    private let registry: TagGroupRegistry

    public init(registry: TagGroupRegistry) {
        self.registry = registry
    }

    /// Generate multi-class training data for a specific group
    public func generateTrainingData(
        for groupName: String,
        from tracks: [TaggedTrack],
        minSamplesPerClass: Int = 20
    ) -> MultiClassTrainingData? {

        guard let classes = registry.groups[groupName] else { return nil }

        var samples: [ClassifiedSample] = []
        var classCounts: [String: Int] = [:]

        for track in tracks {
            guard let features = track.features else { continue }

            // Find which class this track belongs to
            var assignedClass: String?
            for tag in track.tags.sorted() {
                if let className = registry.normalizeTagToClass(tag, inGroup: groupName) {
                    assignedClass = className
                    break
                }
            }

            guard let className = assignedClass else { continue }

            samples.append(ClassifiedSample(trackId: track.id, className: className, features: features))
            classCounts[className, default: 0] += 1
        }

        // Filter to classes with enough samples
        let validClasses = classes.filter { (classCounts[$0] ?? 0) >= minSamplesPerClass }

        // Need at least 2 classes for multi-class
        guard validClasses.count >= 2 else { return nil }

        let validSamples = samples.filter { validClasses.contains($0.className) }

        return MultiClassTrainingData(
            groupName: groupName,
            classes: validClasses.sorted(),
            samples: validSamples
        )
    }

    /// Find all groups that have enough data for training
    public func viableGroups(
        from tracks: [TaggedTrack],
        minSamplesPerClass: Int = 20,
        minClasses: Int = 2
    ) -> [String] {
        registry.groups.keys.compactMap { groupName in
            guard let data = generateTrainingData(for: groupName, from: tracks, minSamplesPerClass: minSamplesPerClass),
                  data.classes.count >= minClasses else { return nil }
            return groupName
        }.sorted()
    }
}
