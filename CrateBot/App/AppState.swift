import SwiftUI
import CrateBotCore

@Observable
final class AppState {
    // Setup state
    var setupComplete: Bool = UserDefaults.standard.bool(forKey: "setupComplete") {
        didSet { UserDefaults.standard.set(setupComplete, forKey: "setupComplete") }
    }

    // Model state
    var modelLoaded = false
    var modelName: String?
    var availableTags: AvailableTags?

    // Navigation
    var currentView: AppView = .tagging
    var settingsOpen = false

    // Tagging preferences
    var taggingPreferences = TaggingPreferences.load()

    // Tagging queue state
    var queuedFiles: [QueuedFile] = []
    var isTagging = false
    var taggingProgress: Double = 0.0

    // Refine queue state
    var refineQueue: [RefineFile] = []
    var selectedRefineFile: RefineFile?

    // Services
    let bookmarkManager = BookmarkManager()
    let audioPlayer = AudioPlayer()

    // Toasts
    var toast: Toast?

    enum AppView: String, CaseIterable {
        case tagging
        case train
        case refine
    }

    struct AvailableTags {
        var genre: [String]
        var timing: [String]
        var mood: [String]
        var descriptive: [String]
    }

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let kind: Kind

        enum Kind { case success, error }
    }

    struct QueuedFile: Identifiable {
        let id = UUID()
        let url: URL
        var status: Status = .pending
        var error: String?

        /// Tags written to the file (populated after successful tagging)
        var writtenTags: WrittenTags?

        enum Status { case pending, processing, complete, error }

        var fileName: String { url.lastPathComponent }

        /// Summary of tags that were written
        var tagsSummary: String? {
            guard let tags = writtenTags else { return nil }
            var parts: [String] = []
            if let genre = tags.userGenre { parts.append("Genre: \(genre)") }
            if !tags.essentiaGenres.isEmpty { parts.append("Genres: \(tags.essentiaGenres.prefix(3).joined(separator: ", "))") }
            if !tags.essentiaMoods.isEmpty { parts.append("Moods: \(tags.essentiaMoods.prefix(3).joined(separator: ", "))") }
            return parts.isEmpty ? nil : parts.joined(separator: " | ")
        }
    }

    /// Tags that were written to a file
    struct WrittenTags {
        // User model predictions (primary)
        var userGenre: String?
        var userTiming: String?
        var userMood: String?
        var userDescriptive: [String] = []

        // Essentia predictions (secondary)
        var essentiaGenres: [String] = []
        var essentiaMoods: [String] = []
        var essentiaInstruments: [String] = []
    }

    struct RefineFile: Identifiable, Equatable {
        let id: UUID
        let url: URL
        var genre: String?
        var mood: [String]
        var timing: String?
        var descriptive: [String]
        var confidences: [String: Float]?
        var hasChanges: Bool = false

        var fileName: String { url.lastPathComponent }

        init(
            id: UUID = UUID(),
            url: URL,
            genre: String? = nil,
            mood: [String] = [],
            timing: String? = nil,
            descriptive: [String] = [],
            confidences: [String: Float]? = nil
        ) {
            self.id = id
            self.url = url
            self.genre = genre
            self.mood = mood
            self.timing = timing
            self.descriptive = descriptive
            self.confidences = confidences
        }

        /// Summary of tags for display in list
        var tagsSummary: String {
            var parts: [String] = []
            if let genre = genre { parts.append(genre) }
            if let timing = timing { parts.append(timing) }
            if !mood.isEmpty { parts.append(mood.joined(separator: ", ")) }
            return parts.isEmpty ? "No tags" : parts.joined(separator: " | ")
        }

        static func == (lhs: RefineFile, rhs: RefineFile) -> Bool {
            lhs.id == rhs.id
        }
    }

    func showToast(_ message: String, kind: Toast.Kind = .success) {
        toast = Toast(message: message, kind: kind)
    }

    func dismissToast() {
        toast = nil
    }
}

struct TaggingPreferences: Codable {
    var genre = FieldPreference(enabled: true, targetField: "TCON")
    var album = FieldPreference(enabled: true, targetField: "TALB")
    var mood = FieldPreference(enabled: true, targetField: "TIT1")
    var comments = FieldPreference(enabled: true, targetField: "COMM")
    var likeness = FieldPreference(enabled: true, targetField: "TIT1")
    var vibes = VibesPreference(enabled: false, shortTargetField: "TXXX:CRATEBOT_VIBE_SHORT", longTargetField: "COMM")
    var hooks = FieldPreference(enabled: false, targetField: "TXXX:CRATEBOT_HOOK")
    var overwrite = true

    struct FieldPreference: Codable {
        var enabled: Bool
        var targetField: String
    }

    struct VibesPreference: Codable {
        var enabled: Bool
        var shortTargetField: String
        var longTargetField: String
    }

    private static let storageKey = "taggingPreferences"

    static func load() -> TaggingPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(TaggingPreferences.self, from: data) else {
            return TaggingPreferences()
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
