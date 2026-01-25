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

    /// Find which group a tag belongs to (supports partial matching)
    public func groupName(for tag: String) -> String? {
        let lowered = tag.lowercased()

        // Direct match
        if let group = tagToGroup[lowered] {
            return group
        }

        // Partial match (e.g., "WalkingBass" contains "Walking")
        for (groupName, classes) in groups {
            for className in classes {
                if lowered.contains(className.lowercased()) {
                    return groupName
                }
            }
        }
        return nil
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

    public static var defaultGroups: TagGroupRegistry {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy", "Deep", "Subby"])
        registry.addGroup(name: "Vibe", tags: ["Dope", "Chill", "Dark", "Uplifting", "Melancholic"])
        registry.addGroup(name: "Energy", tags: ["Low", "Medium", "High", "Peak"])
        registry.addGroup(name: "Cultural", tags: ["Asian", "Latin", "African", "MiddleEastern", "European"])
        return registry
    }
}
