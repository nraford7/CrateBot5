import Foundation

// MARK: - Tag Frame Mapping

/// Maps CrateBot tag categories to ID3 frame identifiers.
///
/// Frame mappings:
/// - genre = "TCON" (Content type) - standard genre frame, used for both genre and timing
/// - timing = "TALB" (Album) - used for timing in our system
/// - mood = "TIT1" (Content group)
/// - comments = "COMM" (Comments) - only the first COMM frame is read/written
/// - vibeShort = "TCOM" (Composer) - short vibe description
/// - vibeDescription = "TIT3" (Subtitle) - detailed vibe description
/// - scene = "TOWN" (File owner) - stores scene classification
/// - hook = "TEXT" (Lyricist) - stores hook description
public enum TagMapping {
    // MARK: - Frame Identifiers

    /// Content type frame - stores genre (if known) or timing
    public static let genre = "TCON"

    /// Album frame - used to store timing information
    public static let timing = "TALB"

    /// Content group frame - stores mood tags
    public static let mood = "TIT1"

    /// Comments frame - stores general comments.
    /// Note: Only the first COMM frame is read; multiple comments are not supported.
    public static let comments = "COMM"

    /// Composer frame - stores short vibe description
    public static let vibeShort = "TCOM"

    /// Subtitle frame - stores detailed vibe description
    public static let vibeDescription = "TIT3"

    /// iTunes Grouping frame (GRP1) - stores the LLM mix-context hint.
    /// Spec called for TXXX:CRATEBOT_MIXHINT, but ID3TagEditor does not expose
    /// the TXXX user-defined-text frame. GRP1 is the closest semantic match
    /// in the supported set: visible in iTunes/Music and most DJ tools, and
    /// not consumed by any other CrateBot write path.
    public static let mixHint = "GRP1"

    /// File owner frame - stores scene tag (TOWN frame in ID3v2.3+)
    /// Note: Using this frame for scene as TXXX is not supported by ID3TagEditor.
    public static let scene = "TOWN"

    /// Lyricist frame - stores hook tag (TEXT frame)
    /// Note: Using this frame for hook as TXXX is not supported by ID3TagEditor.
    public static let hook = "TEXT"

    // MARK: - Essentia Tag Frame Identifiers

    /// Publisher frame - stores Essentia-predicted genres (TPUB)
    public static let essentiaGenres = "TPUB"

    /// Conductor frame - stores Essentia-predicted moods (TPE3)
    public static let essentiaMoods = "TPE3"

    /// Encoded by frame - stores Essentia-predicted instruments (TENC)
    public static let essentiaInstruments = "TENC"

    // MARK: - Known Genres

    /// Set of known genres for genre/timing disambiguation.
    /// If a TCON value is in this set, it's treated as a genre; otherwise as timing.
    public static let knownGenres: Set<String> = [
        "House",
        "Techno",
        "Jungle",
        "Rap",
        "DiscoFunk",
        "PartyBreaks",
        "Acapella",
        "Dub/Reggae"
    ]

    /// Checks if a value should be treated as a genre (vs timing).
    ///
    /// Comparison is case-insensitive.
    ///
    /// - Parameter value: The string value to check
    /// - Returns: `true` if the value is a known genre
    public static func isGenre(_ value: String) -> Bool {
        let lowercasedValue = value.lowercased()
        return knownGenres.contains { $0.lowercased() == lowercasedValue }
    }
}

// MARK: - Extracted Tags

/// Tags extracted from an MP3 file's ID3 metadata.
///
/// All properties are optional as files may not have all tags set.
public struct ExtractedTags: Sendable, Equatable {
    /// The title of the track (TIT2)
    public var title: String?

    /// The artist of the track (TPE1)
    public var artist: String?

    /// The album artist (TPE2) - often used for different purposes
    public var albumArtist: String?

    /// The album name (TALB)
    public var album: String?

    /// The genre of the track (TCON)
    public var genre: String?

    /// The timing/album information (legacy, mapped from TALB)
    public var timing: String?

    /// Mood tags (from content group frame TIT1)
    public var mood: String?

    /// General comments (COMM)
    public var comments: String?

    /// Short vibe description (from composer frame TCOM)
    public var vibeShort: String?

    /// Detailed vibe description (from subtitle frame TIT3)
    public var vibeDescription: String?

    /// Scene tag for track classification (TOWN)
    public var scene: String?

    /// Hook tag describing memorable elements (TEXT)
    public var hook: String?

    /// BPM / Beats per minute (TBPM)
    public var bpm: String?

    /// Year (TYER/TDRC)
    public var year: String?

    /// Publisher (TPUB)
    public var publisher: String?

    /// Conductor (TPE3)
    public var conductor: String?

    /// Encoded by (TENC)
    public var encodedBy: String?

    /// Copyright (TCOP)
    public var copyright: String?

    /// Original artist (TOPE)
    public var originalArtist: String?

    /// Creates a new ExtractedTags instance.
    public init(
        title: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        timing: String? = nil,
        mood: String? = nil,
        comments: String? = nil,
        vibeShort: String? = nil,
        vibeDescription: String? = nil,
        scene: String? = nil,
        hook: String? = nil,
        bpm: String? = nil,
        year: String? = nil,
        publisher: String? = nil,
        conductor: String? = nil,
        encodedBy: String? = nil,
        copyright: String? = nil,
        originalArtist: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.genre = genre
        self.timing = timing
        self.mood = mood
        self.comments = comments
        self.vibeShort = vibeShort
        self.vibeDescription = vibeDescription
        self.scene = scene
        self.hook = hook
        self.bpm = bpm
        self.year = year
        self.publisher = publisher
        self.conductor = conductor
        self.encodedBy = encodedBy
        self.copyright = copyright
        self.originalArtist = originalArtist
    }
}

// MARK: - Write Field Mapping

/// Configuration for which ID3 frames to write each category to.
/// This allows the write operation to match the user's configured field mapping
/// used during training data collection.
public struct WriteFieldMapping: Sendable, Equatable, Codable {
    /// Frame to write genre to (default: TCON)
    public var genreFrame: ID3FrameType

    /// Frame to write timing to (default: TALB)
    public var timingFrame: ID3FrameType

    /// Frame to write mood to (default: TIT1)
    public var moodFrame: ID3FrameType

    /// Frame to write descriptive/comments to (default: COMM)
    public var descriptiveFrame: ID3FrameType

    public init(
        genreFrame: ID3FrameType = .genre,
        timingFrame: ID3FrameType = .album,
        moodFrame: ID3FrameType = .contentGroup,
        descriptiveFrame: ID3FrameType = .comments
    ) {
        self.genreFrame = genreFrame
        self.timingFrame = timingFrame
        self.moodFrame = moodFrame
        self.descriptiveFrame = descriptiveFrame
    }

    /// Default field mapping (legacy behavior)
    public static let `default` = WriteFieldMapping()
}

/// ID3 frame types for configurable field mapping
public enum ID3FrameType: String, Sendable, CaseIterable, Codable {
    case title          // TIT2
    case artist         // TPE1
    case albumArtist    // TPE2
    case album          // TALB
    case genre          // TCON
    case contentGroup   // TIT1 (Grouping)
    case comments       // COMM
    case composer       // TCOM
    case subtitle       // TIT3
    case conductor      // TPE3
    case lyricist       // TEXT
    case fileOwner      // TOWN

    public var frameID: String {
        switch self {
        case .title: return "TIT2"
        case .artist: return "TPE1"
        case .albumArtist: return "TPE2"
        case .album: return "TALB"
        case .genre: return "TCON"
        case .contentGroup: return "TIT1"
        case .comments: return "COMM"
        case .composer: return "TCOM"
        case .subtitle: return "TIT3"
        case .conductor: return "TPE3"
        case .lyricist: return "TEXT"
        case .fileOwner: return "TOWN"
        }
    }

    public var displayName: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .albumArtist: return "Album Artist"
        case .album: return "Album"
        case .genre: return "Genre"
        case .contentGroup: return "Grouping"
        case .comments: return "Comments"
        case .composer: return "Composer"
        case .subtitle: return "Subtitle"
        case .conductor: return "Conductor"
        case .lyricist: return "Lyricist"
        case .fileOwner: return "File Owner"
        }
    }
}

// MARK: - Tags to Write

/// Tags to write to an MP3 file's ID3 metadata.
///
/// All properties are optional; only non-nil values will be written.
public struct TagsToWrite: Sendable, Equatable {
    /// The genre of the track (e.g., "House", "Techno")
    public var genre: String?

    /// The sub-genre from Essentia predictions (e.g., "Deep House", "Tech House")
    public var subGenre: String?

    /// The timing/album information
    public var timing: String?

    /// Mood tags (to content group frame)
    public var mood: String?

    /// General comments
    public var comments: String?

    /// Short vibe description (to composer frame)
    public var vibeShort: String?

    /// Detailed vibe description (to subtitle frame)
    public var vibeDescription: String?

    /// DJ mix-context hint (to iTunes Grouping frame GRP1)
    public var mixHint: String?

    /// Scene tag for track classification
    public var scene: String?

    /// Hook tag describing memorable elements
    public var hook: String?

    // MARK: - Essentia-Predicted Tags

    /// Essentia-predicted genres (to publisher frame TPUB)
    public var essentiaGenres: String?

    /// Essentia-predicted moods (to conductor frame TPE3)
    public var essentiaMoods: String?

    /// Essentia-predicted instruments (to encoded by frame TENC)
    public var essentiaInstruments: String?

    /// Whether to overwrite existing tags (default: true)
    public var overwrite: Bool

    /// Field mapping configuration for which ID3 frames to write to.
    /// When nil, uses default mapping (genre=TCON, timing=TALB, mood=TIT1, comments=COMM)
    public var fieldMapping: WriteFieldMapping?

    /// Creates a new TagsToWrite instance.
    public init(
        genre: String? = nil,
        subGenre: String? = nil,
        timing: String? = nil,
        mood: String? = nil,
        comments: String? = nil,
        vibeShort: String? = nil,
        vibeDescription: String? = nil,
        mixHint: String? = nil,
        scene: String? = nil,
        hook: String? = nil,
        essentiaGenres: String? = nil,
        essentiaMoods: String? = nil,
        essentiaInstruments: String? = nil,
        overwrite: Bool = true,
        fieldMapping: WriteFieldMapping? = nil
    ) {
        self.genre = genre
        self.subGenre = subGenre
        self.timing = timing
        self.mood = mood
        self.comments = comments
        self.vibeShort = vibeShort
        self.vibeDescription = vibeDescription
        self.mixHint = mixHint
        self.scene = scene
        self.hook = hook
        self.essentiaGenres = essentiaGenres
        self.essentiaMoods = essentiaMoods
        self.essentiaInstruments = essentiaInstruments
        self.overwrite = overwrite
        self.fieldMapping = fieldMapping
    }

    /// Returns `true` if all tag values are nil.
    public var isEmpty: Bool {
        genre == nil &&
        subGenre == nil &&
        timing == nil &&
        mood == nil &&
        comments == nil &&
        vibeShort == nil &&
        vibeDescription == nil &&
        mixHint == nil &&
        scene == nil &&
        hook == nil &&
        essentiaGenres == nil &&
        essentiaMoods == nil &&
        essentiaInstruments == nil
    }
}
