import Foundation

/// Maps a user-defined tag to one or more Essentia pre-trained predictions
public struct TagFallbackMapping: Codable, Sendable, Identifiable, Equatable {
    public var id: String { userTag }

    /// The user's tag name (e.g., "dark", "chill")
    public var userTag: String

    /// Which Essentia model to use for this tag
    public var essentiaSource: EssentiaSource

    /// The specific labels from the Essentia model (e.g., ["dark", "heavy"])
    /// If ANY label matches above threshold, the tag is applied
    public var essentiaLabels: [String]

    /// Legacy single label support (for migration)
    public var essentiaLabel: String {
        get { essentiaLabels.first ?? "" }
        set { essentiaLabels = newValue.isEmpty ? [] : [newValue] }
    }

    /// Legacy threshold (no longer used - inherits global strictness)
    @available(*, deprecated, message: "Threshold now inherits from global strictness setting")
    public var threshold: Float { 0.3 }

    public init(userTag: String, essentiaSource: EssentiaSource, essentiaLabels: [String]) {
        self.userTag = userTag
        self.essentiaSource = essentiaSource
        self.essentiaLabels = essentiaLabels
    }

    /// Legacy initializer for migration
    public init(userTag: String, essentiaSource: EssentiaSource, essentiaLabel: String, threshold: Float = 0.3) {
        self.userTag = userTag
        self.essentiaSource = essentiaSource
        self.essentiaLabels = essentiaLabel.isEmpty ? [] : [essentiaLabel]
    }

    // Custom coding for backward compatibility
    private enum CodingKeys: String, CodingKey {
        case userTag, essentiaSource, essentiaLabels, essentiaLabel, threshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userTag = try container.decode(String.self, forKey: .userTag)
        essentiaSource = try container.decode(EssentiaSource.self, forKey: .essentiaSource)

        // Try new format first, fall back to legacy single label
        if let labels = try? container.decode([String].self, forKey: .essentiaLabels) {
            essentiaLabels = labels
        } else if let singleLabel = try? container.decode(String.self, forKey: .essentiaLabel) {
            essentiaLabels = singleLabel.isEmpty ? [] : [singleLabel]
        } else {
            essentiaLabels = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userTag, forKey: .userTag)
        try container.encode(essentiaSource, forKey: .essentiaSource)
        try container.encode(essentiaLabels, forKey: .essentiaLabels)
    }

    /// Available Essentia prediction sources
    public enum EssentiaSource: String, Codable, Sendable, CaseIterable {
        case mood = "mood"
        case genre = "genre"
        case instrument = "instrument"

        public var displayName: String {
            switch self {
            case .mood: return "Mood/Theme"
            case .genre: return "Genre"
            case .instrument: return "Instrument"
            }
        }

        /// Available labels for this source
        public var availableLabels: [String] {
            switch self {
            case .mood: return EssentiaLabels.moodTheme
            case .genre: return EssentiaLabels.genres
            case .instrument: return EssentiaLabels.instruments
            }
        }
    }
}

/// Configuration containing all fallback mappings
public struct FallbackMappingConfig: Codable, Sendable {
    /// All configured fallback mappings (custom user mappings)
    public var mappings: [TagFallbackMapping]

    /// Whether fallback mappings are enabled
    public var enabled: Bool

    /// Whether to use auto-generated default mappings instead of custom
    public var useDefaultMappings: Bool

    public init(mappings: [TagFallbackMapping] = [], enabled: Bool = true, useDefaultMappings: Bool = true) {
        self.mappings = mappings
        self.enabled = enabled
        self.useDefaultMappings = useDefaultMappings
    }

    // Backward compatible decoding
    private enum CodingKeys: String, CodingKey {
        case mappings, enabled, useDefaultMappings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappings = try container.decodeIfPresent([TagFallbackMapping].self, forKey: .mappings) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        useDefaultMappings = try container.decodeIfPresent(Bool.self, forKey: .useDefaultMappings) ?? true
    }

    /// Get mapping for a specific user tag
    public func mapping(for userTag: String) -> TagFallbackMapping? {
        mappings.first { $0.userTag.lowercased() == userTag.lowercased() }
    }

    /// Add or update a mapping
    public mutating func setMapping(_ mapping: TagFallbackMapping) {
        if let index = mappings.firstIndex(where: { $0.userTag.lowercased() == mapping.userTag.lowercased() }) {
            mappings[index] = mapping
        } else {
            mappings.append(mapping)
        }
    }

    /// Remove a mapping
    public mutating func removeMapping(for userTag: String) {
        mappings.removeAll { $0.userTag.lowercased() == userTag.lowercased() }
    }
}

/// Manages persistence of fallback mappings
public final class FallbackMappingManager: Sendable {
    private static let storageKey = "fallbackMappingConfig"

    public init() {}

    /// Load saved configuration
    public func load() -> FallbackMappingConfig {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let config = try? JSONDecoder().decode(FallbackMappingConfig.self, from: data) else {
            return FallbackMappingConfig()
        }
        return config
    }

    /// Save configuration
    public func save(_ config: FallbackMappingConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Generate intelligent default mappings for a list of user tags
    /// This creates comprehensive mappings based on tag name analysis
    public func generateDefaultMappings(for userTags: [String]) -> [TagFallbackMapping] {
        var mappings: [TagFallbackMapping] = []

        for userTag in userTags {
            if let mapping = generateDefaultMapping(for: userTag) {
                mappings.append(mapping)
            }
        }

        return mappings
    }

    /// Generate a default mapping for a single tag
    private func generateDefaultMapping(for userTag: String) -> TagFallbackMapping? {
        let normalized = userTag.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Comprehensive mapping rules organized by category

        // MOOD/ENERGY MAPPINGS
        let moodMappings: [String: [String]] = [
            // Energy levels
            "dark": ["dark", "heavy", "dramatic"],
            "dreamy": ["dream", "soundscape", "soft"],
            "chill": ["relaxing", "calm", "soft"],
            "chilled": ["relaxing", "calm", "soft"],
            "mellow": ["calm", "relaxing", "soft"],
            "energetic": ["energetic", "powerful", "action"],
            "high energy": ["energetic", "powerful", "fast"],
            "low energy": ["calm", "slow", "soft"],
            "intense": ["powerful", "dramatic", "heavy"],
            "aggressive": ["heavy", "powerful", "action"],

            // Emotional
            "happy": ["happy", "fun", "upbeat", "positive"],
            "sad": ["sad", "melancholic", "emotional"],
            "emotional": ["emotional", "dramatic", "melancholic"],
            "melancholic": ["melancholic", "sad", "emotional"],
            "uplifting": ["uplifting", "hopeful", "inspiring", "positive"],
            "euphoric": ["uplifting", "energetic", "happy"],
            "romantic": ["romantic", "love", "emotional"],

            // Atmosphere
            "atmospheric": ["soundscape", "space", "deep"],
            "ambient": ["soundscape", "calm", "soft"],
            "epic": ["epic", "dramatic", "powerful", "film"],
            "cinematic": ["film", "dramatic", "epic", "trailer"],
            "dramatic": ["dramatic", "emotional", "powerful"],
            "hypnotic": ["deep", "meditative", "soundscape"],
            "trippy": ["dream", "space", "deep"],
            "psychedelic": ["dream", "space", "retro"],
            "mystical": ["space", "soundscape", "deep"],
            "cosmic": ["space", "soundscape", "deep"],

            // Character
            "funky": ["groovy", "fun", "retro"],
            "groovy": ["groovy", "fun", "retro"],
            "bouncy": ["fun", "upbeat", "happy"],
            "driving": ["energetic", "powerful", "fast"],
            "pumping": ["energetic", "powerful", "party"],
            "sexy": ["sexy", "groovy", "deep"],
            "sensual": ["sexy", "romantic", "soft"],
            "playful": ["fun", "happy", "positive"],
            "warm": ["soft", "romantic", "calm"],
            "cool": ["cool", "groovy", "retro"],

            // Use cases
            "party": ["party", "fun", "energetic"],
            "workout": ["sport", "energetic", "powerful"],
            "meditation": ["meditative", "calm", "relaxing"],
            "focus": ["calm", "background", "soft"],

            // Tempo indicators
            "fast": ["fast", "energetic", "action"],
            "slow": ["slow", "calm", "soft"],
            "building": ["dramatic", "energetic", "powerful"],
            "peak": ["energetic", "powerful", "action"]
        ]

        // GENRE MAPPINGS - map to Essentia genre labels
        let genreMappings: [String: [String]] = [
            "house": ["Electronic---House", "Electronic---Deep House", "Electronic---Tech House"],
            "deep house": ["Electronic---Deep House", "Electronic---House"],
            "tech house": ["Electronic---Tech House", "Electronic---Minimal Techno"],
            "techno": ["Electronic---Techno", "Electronic---Minimal Techno", "Electronic---Tech House"],
            "minimal": ["Electronic---Minimal", "Electronic---Minimal Techno"],
            "trance": ["Electronic---Trance", "Electronic---Progressive Trance"],
            "progressive": ["Electronic---Progressive House", "Electronic---Progressive Trance"],
            "disco": ["Electronic---Disco", "Electronic---Nu-Disco", "Funk / Soul---Disco"],
            "nu disco": ["Electronic---Nu-Disco", "Electronic---Disco"],
            "electro": ["Electronic---Electro", "Electronic---Electro House"],
            "breaks": ["Electronic---Breaks", "Electronic---Breakbeat"],
            "breakbeat": ["Electronic---Breakbeat", "Electronic---Breaks"],
            "dnb": ["Electronic---Drum n Bass", "Electronic---Jungle"],
            "drum and bass": ["Electronic---Drum n Bass", "Electronic---Jungle"],
            "jungle": ["Electronic---Jungle", "Electronic---Drum n Bass"],
            "dubstep": ["Electronic---Dubstep", "Electronic---Grime"],
            "garage": ["Electronic---UK Garage", "Electronic---Garage House"],
            "uk garage": ["Electronic---UK Garage", "Electronic---Speed Garage"],
            "ambient": ["Electronic---Ambient", "Electronic---Downtempo"],
            "downtempo": ["Electronic---Downtempo", "Electronic---Ambient", "Electronic---Trip Hop"],
            "trip hop": ["Electronic---Trip Hop", "Electronic---Downtempo"],
            "hip hop": ["Hip Hop---Boom Bap", "Hip Hop---Instrumental", "Electronic---Hip Hop"],
            "trap": ["Hip Hop---Trap", "Hip Hop---Bass Music"],
            "funk": ["Funk / Soul---Funk", "Funk / Soul---Boogie"],
            "soul": ["Funk / Soul---Soul", "Funk / Soul---Neo Soul"],
            "jazz": ["Jazz---Contemporary Jazz", "Jazz---Jazz-Funk", "Jazz---Fusion"],
            "latin": ["Latin---Salsa", "Latin---Cumbia", "Electronic---Latin"],
            "afro": ["Funk / Soul---Afrobeat", "Jazz---Afrobeat"],
            "reggae": ["Reggae---Reggae", "Reggae---Dub", "Reggae---Roots Reggae"],
            "dub": ["Reggae---Dub", "Electronic---Dub", "Electronic---Dub Techno"],
            "rock": ["Rock---Classic Rock", "Rock---Indie Rock"],
            "indie": ["Rock---Indie Rock", "Pop---Indie Pop"]
        ]

        // Check mood mappings first (most common for descriptive tags)
        for (key, labels) in moodMappings {
            if normalized == key || normalized.contains(key) {
                return TagFallbackMapping(
                    userTag: userTag,
                    essentiaSource: .mood,
                    essentiaLabels: labels
                )
            }
        }

        // Check genre mappings
        for (key, labels) in genreMappings {
            if normalized == key || normalized.contains(key) {
                return TagFallbackMapping(
                    userTag: userTag,
                    essentiaSource: .genre,
                    essentiaLabels: labels
                )
            }
        }

        // Try exact match in Essentia mood labels
        let moodLabels = EssentiaLabels.moodTheme
        if let exactMatch = moodLabels.first(where: { $0.lowercased() == normalized }) {
            return TagFallbackMapping(
                userTag: userTag,
                essentiaSource: .mood,
                essentiaLabels: [exactMatch]
            )
        }

        // Try partial match in Essentia mood labels
        let partialMoodMatches = moodLabels.filter { $0.lowercased().contains(normalized) || normalized.contains($0.lowercased()) }
        if !partialMoodMatches.isEmpty {
            return TagFallbackMapping(
                userTag: userTag,
                essentiaSource: .mood,
                essentiaLabels: partialMoodMatches
            )
        }

        // Try genre label matching (search in subgenre names)
        let genreLabels = EssentiaLabels.genres
        let matchingGenres = genreLabels.filter { label in
            if let separatorRange = label.range(of: "---") {
                let subgenre = String(label[separatorRange.upperBound...]).lowercased()
                return subgenre.contains(normalized) || normalized.contains(subgenre)
            }
            return false
        }
        if !matchingGenres.isEmpty {
            return TagFallbackMapping(
                userTag: userTag,
                essentiaSource: .genre,
                essentiaLabels: Array(matchingGenres.prefix(5)) // Limit to 5 matches
            )
        }

        // No match found - return nil (tag won't have fallback)
        return nil
    }

    /// Suggest auto-matches for user tags based on Essentia labels
    public func suggestMappings(for userTags: [String]) -> [TagFallbackMapping] {
        var suggestions: [TagFallbackMapping] = []

        for userTag in userTags {
            let normalizedTag = userTag.lowercased().trimmingCharacters(in: .whitespaces)

            // Try exact match in mood
            if let match = findExactMatch(normalizedTag, in: EssentiaLabels.moodTheme) {
                suggestions.append(TagFallbackMapping(
                    userTag: userTag,
                    essentiaSource: .mood,
                    essentiaLabels: [match]
                ))
                continue
            }

            // Try exact match in genre
            if let match = findExactMatch(normalizedTag, in: EssentiaLabels.genres) {
                suggestions.append(TagFallbackMapping(
                    userTag: userTag,
                    essentiaSource: .genre,
                    essentiaLabels: [match]
                ))
                continue
            }

            // Try exact match in instruments
            if let match = findExactMatch(normalizedTag, in: EssentiaLabels.instruments) {
                suggestions.append(TagFallbackMapping(
                    userTag: userTag,
                    essentiaSource: .instrument,
                    essentiaLabels: [match]
                ))
                continue
            }

            // Try fuzzy matching for common variations
            if let suggestion = findFuzzyMatch(normalizedTag) {
                suggestions.append(suggestion.withUserTag(userTag))
            }
        }

        return suggestions
    }

    private func findExactMatch(_ tag: String, in labels: [String]) -> String? {
        labels.first { $0.lowercased() == tag }
    }

    private func findFuzzyMatch(_ tag: String) -> TagFallbackMapping? {
        // Common synonyms and variations
        let moodSynonyms: [String: String] = [
            "chill": "relaxing",
            "chilled": "relaxing",
            "chillout": "relaxing",
            "mellow": "calm",
            "peaceful": "calm",
            "intense": "powerful",
            "aggressive": "heavy",
            "pumping": "energetic",
            "driving": "energetic",
            "high-energy": "energetic",
            "high energy": "energetic",
            "hype": "energetic",
            "euphoric": "uplifting",
            "anthemic": "epic",
            "atmospheric": "soundscape",
            "ambient": "soundscape",
            "dreamy": "dream",
            "trippy": "dream",
            "feel-good": "happy",
            "feelgood": "happy",
            "feel good": "happy",
            "joyful": "happy",
            "cheerful": "happy",
            "gloomy": "melancholic",
            "depressing": "sad",
            "sensual": "sexy",
            "seductive": "sexy",
            "nostalgic": "retro",
            "old-school": "retro",
            "oldschool": "retro",
            "groovey": "groovy",
            "funky": "groovy",
            "bouncy": "fun",
            "playful": "fun",
            "cinematic": "film",
            "theatrical": "dramatic",
            "mystical": "space",
            "cosmic": "space",
            "futuristic": "space",
            "workout": "sport",
            "exercise": "sport",
            "gym": "sport",
            "meditation": "meditative",
            "zen": "meditative",
            "spiritual": "meditative"
        ]

        if let essentiaLabel = moodSynonyms[tag] {
            return TagFallbackMapping(
                userTag: tag,
                essentiaSource: .mood,
                essentiaLabels: [essentiaLabel]
            )
        }

        return nil
    }
}

extension TagFallbackMapping {
    /// Create a copy with a different user tag
    func withUserTag(_ newUserTag: String) -> TagFallbackMapping {
        TagFallbackMapping(
            userTag: newUserTag,
            essentiaSource: essentiaSource,
            essentiaLabels: essentiaLabels
        )
    }
}
