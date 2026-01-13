import SwiftUI
import CrateBotCore

/// Available ID3 fields that can be mapped to training categories - comprehensive iTunes support
enum ID3Field: String, CaseIterable, Identifiable, Codable {
    // Common fields
    case title = "Title (TIT2)"
    case artist = "Artist (TPE1)"
    case albumArtist = "Album Artist (TPE2)"
    case album = "Album (TALB)"
    case genre = "Genre (TCON)"
    case contentGroup = "Grouping (TIT1)"
    case comments = "Comments (COMM)"
    case composer = "Composer (TCOM)"
    case subtitle = "Subtitle (TIT3)"
    case conductor = "Conductor (TPE3)"
    case lyricist = "Lyricist (TEXT)"
    case fileOwner = "File Owner (TOWN)"

    // Additional metadata
    case bpm = "BPM (TBPM)"
    case year = "Year (TYER)"
    case publisher = "Publisher (TPUB)"
    case encodedBy = "Encoded By (TENC)"

    var id: String { rawValue }

    var shortName: String {
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
        case .bpm: return "BPM"
        case .year: return "Year"
        case .publisher: return "Publisher"
        case .encodedBy: return "Encoded By"
        }
    }

    var description: String {
        switch self {
        case .title: return "Song title (TIT2)"
        case .artist: return "Artist name (TPE1)"
        case .albumArtist: return "Album Artist - often repurposed (TPE2)"
        case .album: return "Album name (TALB)"
        case .genre: return "Genre field (TCON)"
        case .contentGroup: return "Grouping field (TIT1)"
        case .comments: return "Comments field (COMM)"
        case .composer: return "Composer field (TCOM)"
        case .subtitle: return "Subtitle/description (TIT3)"
        case .conductor: return "Conductor field (TPE3)"
        case .lyricist: return "Lyricist field (TEXT)"
        case .fileOwner: return "File Owner field (TOWN)"
        case .bpm: return "Beats per minute (TBPM)"
        case .year: return "Year (TYER)"
        case .publisher: return "Publisher/Label (TPUB)"
        case .encodedBy: return "Encoded by (TENC)"
        }
    }

    /// Convert to CrateBotCore's ID3FieldType
    var coreFieldType: TrainingDataCollector.ID3FieldType {
        switch self {
        case .title: return .title
        case .artist: return .artist
        case .albumArtist: return .albumArtist
        case .album: return .album
        case .genre: return .genre
        case .contentGroup: return .contentGroup
        case .comments: return .comments
        case .composer: return .composer
        case .subtitle: return .subtitle
        case .conductor: return .conductor
        case .lyricist: return .lyricist
        case .fileOwner: return .fileOwner
        case .bpm: return .bpm
        case .year: return .year
        case .publisher: return .publisher
        case .encodedBy: return .encodedBy
        }
    }
}

/// Configuration for mapping ID3 fields to training categories
struct TagMappingConfiguration: Equatable, Codable {
    var genreField: ID3Field = .genre
    var timingField: ID3Field = .album
    var moodField: ID3Field = .contentGroup
    var descriptiveField: ID3Field = .comments

    static let `default` = TagMappingConfiguration()

    /// Convert to CrateBotCore's TagFieldMapping
    var coreMapping: TrainingDataCollector.TagFieldMapping {
        .init(
            genreField: genreField.coreFieldType,
            timingField: timingField.coreFieldType,
            moodField: moodField.coreFieldType,
            descriptiveField: descriptiveField.coreFieldType
        )
    }
}

@Observable
final class ModelLabState {
    // MARK: - Tag Mapping Configuration

    /// User-configurable mapping of ID3 fields to training categories
    var tagMapping = TagMappingConfiguration()

    // MARK: - Experiment Configuration

    /// Selected music folders for experimentation
    var selectedFolders: [URL] = []

    /// Sample size for experiments
    var sampleSize: SampleSize = .balanced

    /// Selected feature extractors
    var selectedExtractors: Set<String> = ["spectral"]

    /// Number of cross-validation folds
    var folds: Int = 5

    /// Tags selected for experimentation
    var experimentTags: Set<String> = []

    /// All discovered tags with counts
    var allTags: [String: Int] = [:]

    // MARK: - Experiment State

    /// Whether an experiment is running
    var isExperimentRunning = false

    /// Current experiment progress
    var experimentProgress: ExperimentProgress?

    /// Most recent experiment result
    var currentExperiment: ExperimentResult?

    /// History of experiment results
    var experimentHistory: [ExperimentResult] = []

    /// Current error message
    var errorMessage: String?

    // MARK: - Available Extractors (expandable for future)

    static let availableExtractors: [(id: String, name: String, available: Bool)] = [
        ("spectral", "Spectral (32 features)", true),
        ("soundAnalysis", "Apple SoundAnalysis", false),
        ("panns", "PANNs (~150MB)", false),
        ("clap", "CLAP (~200MB)", false)
    ]

    // MARK: - Training State (Legacy)

    var trainingStatus: TrainingStatus = .idle
    var trainingPhase: String = ""
    var trainingProgress: Double = 0
    var currentFile: String?
    var filesProcessed: Int = 0
    var totalFiles: Int = 0
    var samplesCollected: Int = 0
    var startTime: Date?
    var logs: [LogEntry] = []

    // Discovered tags from scanning
    var discoveredTags: DiscoveredTags?

    // Selected tags for training
    var selectedTags: SelectedTags?

    // Training directory
    var trainingDirectory: URL?
    var modelName: String = "cratebot"

    // Services
    let bookmarkManager = BookmarkManager()

    enum TrainingStatus: String {
        case idle
        case scanning
        case running
        case paused
        case completed
        case failed
        case cancelled
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        enum Level: String {
            case info, warning, error
        }
    }

    struct DiscoveredTags {
        var genre: [String: Int] = [:]
        var timing: [String: Int] = [:]
        var mood: [String: Int] = [:]
        var descriptive: [String: Int] = [:]
        var totalFiles: Int = 0
    }

    struct SelectedTags {
        var genre: [String]
        var timing: [String]
        var mood: [String]
        var descriptive: [String]
    }

    func addLog(_ message: String, level: LogEntry.Level = .info) {
        logs.append(LogEntry(timestamp: Date(), level: level, message: message))
    }

    func clearLogs() {
        logs.removeAll()
    }

    func reset() {
        trainingStatus = .idle
        trainingPhase = ""
        trainingProgress = 0
        currentFile = nil
        filesProcessed = 0
        totalFiles = 0
        samplesCollected = 0
        startTime = nil
        discoveredTags = nil
        selectedTags = nil
        logs.removeAll()
    }

    // MARK: - Experiment Actions

    func addFolder(_ url: URL) {
        do {
            try bookmarkManager.addFolderAccess(url)
            if !selectedFolders.contains(url) {
                selectedFolders.append(url)
            }
        } catch {
            errorMessage = "Failed to add folder: \(error.localizedDescription)"
        }
    }

    func removeFolder(_ url: URL) {
        bookmarkManager.removeFolderAccess(url)
        selectedFolders.removeAll { $0 == url }
    }

    func resetExperiment() {
        isExperimentRunning = false
        experimentProgress = nil
        errorMessage = nil
    }
}
