import Foundation

/// Registry of mutually exclusive tag groups for multi-class classification
public struct TagGroupRegistry: Codable, Sendable, Equatable {

    /// Map of group name to array of class names
    public private(set) var groups: [String: [String]] = [:]

    /// Reverse lookup: tag → group name
    private var tagToGroup: [String: String] = [:]

    public init() {}

    public init(groups: [String: [String]]) {
        self.groups = groups
        rebuildIndex()
    }

    public mutating func addGroup(name: String, tags: [String]) {
        groups[name] = tags
        for tag in tags {
            tagToGroup[tag.lowercased()] = name
        }
    }

    public mutating func removeGroup(name: String) {
        if let tags = groups[name] {
            for tag in tags {
                tagToGroup.removeValue(forKey: tag.lowercased())
            }
        }
        groups.removeValue(forKey: name)
    }

    /// Find which group a tag belongs to (with word-boundary matching)
    public func groupName(for tag: String) -> String? {
        let lowered = tag.lowercased()

        // Direct match first
        if let group = tagToGroup[lowered] {
            return group
        }

        // Word-boundary partial match: className must appear at a word boundary
        // and any suffix must relate to the group name
        for (groupName, classes) in groups {
            for className in classes {
                if matchesAsWord(className, in: tag, groupName: groupName) {
                    return groupName
                }
            }
        }
        return nil
    }

    /// Check if className appears as a complete word or at word boundary
    /// and any suffix after the className relates to the group name
    private func matchesAsWord(_ className: String, in tag: String, groupName: String) -> Bool {
        let classLower = className.lowercased()
        let tagLower = tag.lowercased()

        if tagLower == classLower { return true }

        // Find the range in the lowercased string
        guard let lowerRange = tagLower.range(of: classLower) else { return false }

        let startIndex = lowerRange.lowerBound
        let endIndex = lowerRange.upperBound

        // Valid start: at beginning OR preceded by non-letter OR is uppercase in original
        let validStart: Bool
        if startIndex == tag.startIndex {
            validStart = true
        } else {
            let prevChar = tag[tag.index(before: startIndex)]
            let matchStartChar = tag[startIndex]
            validStart = !prevChar.isLetter || matchStartChar.isUppercase
        }

        guard validStart else { return false }

        // Valid end: at end OR followed by separator OR suffix relates to group name
        if endIndex == tag.endIndex {
            return true
        }

        let nextChar = tag[endIndex]

        // If followed by a separator (non-letter), it's a word boundary
        if !nextChar.isLetter {
            return true
        }

        // If followed by a letter, the suffix must contain part of the group name
        let suffix = String(tagLower[endIndex...])
        let groupLower = groupName.lowercased()

        // Check if suffix contains any significant part of the group name (3+ chars)
        // or if the group name contains the suffix
        return suffixRelatesTo(suffix: suffix, groupName: groupLower)
    }

    /// Check if a suffix relates to the group name
    private func suffixRelatesTo(suffix: String, groupName: String) -> Bool {
        // Direct containment either way
        if suffix.contains(groupName) || groupName.contains(suffix) {
            return true
        }

        // Check for partial overlap (at least 3 characters)
        let minOverlap = 3
        for length in stride(from: min(suffix.count, groupName.count), through: minOverlap, by: -1) {
            let groupPrefix = String(groupName.prefix(length))
            if suffix.hasPrefix(groupPrefix) {
                return true
            }
        }

        return false
    }

    /// Normalize a tag to its canonical class name within a group
    public func normalizeTagToClass(_ tag: String, inGroup groupName: String) -> String? {
        guard let classes = groups[groupName] else { return nil }
        let lowered = tag.lowercased()

        // Exact match
        if let match = classes.first(where: { $0.lowercased() == lowered }) {
            return match
        }
        // Partial match
        if let match = classes.first(where: { lowered.contains($0.lowercased()) }) {
            return match
        }
        return nil
    }

    public func isGrouped(_ tag: String) -> Bool {
        groupName(for: tag) != nil
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case groups }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decode([String: [String]].self, forKey: .groups)
        rebuildIndex()
    }

    private mutating func rebuildIndex() {
        tagToGroup = [:]
        for (groupName, tags) in groups {
            for tag in tags {
                tagToGroup[tag.lowercased()] = groupName
            }
        }
    }

    // MARK: - Default Groups for Subjective Tags

    public static let defaultGroups = TagGroupRegistry(groups: [
        "BassType": ["Punchy", "Walking", "BoomingBass", "GrindyBass"],
        "VocalType": ["Singing", "Chanting", "Spoken Word", "Rap", "Instrumental"],
        "Energy": ["Low", "Medium", "High", "Peak"],
        "Cultural": ["Asian", "Latin", "African", "MiddleEastern", "European"]
    ])
}
