import Foundation

/// Sub-categories for organizing descriptive tags
public enum DescriptiveSubCategory: String, CaseIterable, Codable, Sendable {
    case bassType = "BassType"
    case rhythm = "Rhythm"
    case style = "Style"
    case vibes = "Vibes"
    case instruments = "Instruments"
    case vocalType = "VocalType"
}

/// Maps descriptive tags to their sub-categories for structured output
public struct DescriptiveTagMapping: Sendable {

    /// All tag-to-subcategory mappings
    public static let mapping: [String: DescriptiveSubCategory] = [
        // BassType (multi-class)
        "Punchy": .bassType,
        "Walking": .bassType,
        "BoomingBass": .bassType,
        "GrindyBass": .bassType,

        // Rhythm (binary)
        "Broken": .rhythm,
        "Swung": .rhythm,
        "Driving": .rhythm,
        "Loopy": .rhythm,

        // Style (binary)
        "Afro": .style,
        "Electro": .style,
        "Poppy": .style,
        "Disco": .style,
        "Classic": .style,

        // Vibes (binary)
        "Fun": .vibes,
        "Funky": .vibes,
        "Bouncy": .vibes,
        "Dreamy": .vibes,
        "Emotional": .vibes,
        "Epic": .vibes,
        "Happy": .vibes,
        "Joyful": .vibes,
        "Jazzy": .vibes,
        "Melodic": .vibes,
        "Soulful": .vibes,
        "Musical": .vibes,
        "Techy": .vibes,
        "Tropical": .vibes,
        "Dubby": .vibes,
        "Glitchy": .vibes,
        "Floating": .vibes,
        "Spacey": .vibes,
        "Aggressive": .vibes,
        "Grindy": .vibes,
        "Dark": .vibes,
        "Dope": .vibes,
        "Chill": .vibes,
        "Uplifting": .vibes,
        "Melancholic": .vibes,
        "Head Nodding": .vibes,

        // Instruments (binary)
        "Piano": .instruments,
        "Organ": .instruments,
        "Guitar": .instruments,
        "Horns": .instruments,
        "Congas": .instruments,
        "Hi Hats": .instruments,
        "Pads": .instruments,
        "Sweeps": .instruments,
        "Arpeggiated": .instruments,
        "Beats": .instruments,

        // VocalType (multi-class)
        "Singing": .vocalType,
        "Chanting": .vocalType,
        "Spoken Word": .vocalType,
        "Rap": .vocalType,
        "Instrumental": .vocalType,
    ]

    /// Reverse mapping: sub-category to tags
    private static let reverseMapping: [DescriptiveSubCategory: [String]] = {
        var result: [DescriptiveSubCategory: [String]] = [:]
        for (tag, category) in mapping {
            result[category, default: []].append(tag)
        }
        return result
    }()

    /// Get the sub-category for a tag, or nil if unknown
    public static func subCategory(for tag: String) -> DescriptiveSubCategory? {
        return mapping[tag]
    }

    /// Get all tags for a given sub-category
    public static func tags(for subCategory: DescriptiveSubCategory) -> [String] {
        return reverseMapping[subCategory] ?? []
    }

    /// Organize an array of tags by sub-category
    public static func organize(_ tags: [String]) -> [DescriptiveSubCategory: [String]] {
        var result: [DescriptiveSubCategory: [String]] = [:]
        for tag in tags {
            if let category = subCategory(for: tag) {
                result[category, default: []].append(tag)
            }
        }
        return result
    }

    /// Flatten organized tags back to array in sub-category order
    public static func flatten(_ organized: [DescriptiveSubCategory: [String]]) -> [String] {
        var result: [String] = []
        for category in DescriptiveSubCategory.allCases {
            if let tags = organized[category] {
                result.append(contentsOf: tags)
            }
        }
        return result
    }
}
