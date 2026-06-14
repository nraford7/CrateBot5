import SwiftUI
import CrateBotCore
import os.log

private let logger = Logger(subsystem: "com.cratebot", category: "AppState")

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
    var loadedTagNames: [String] = []
    var isLoadingModel = false
    var modelLoadingProgress: Double = 0.0

    // Navigation
    var currentView: AppView = .tagging
    var settingsOpen = false

    // Tagging preferences (auto-saves on change)
    var taggingPreferences = TaggingPreferences.load() {
        didSet { taggingPreferences.save() }
    }

    // Fallback mappings for tags without trained classifiers
    var fallbackMappingConfig: FallbackMappingConfig = FallbackMappingManager().load()

    // Tagging queue state
    var queuedFiles: [QueuedFile] = []
    var isTagging = false
    var isTaggingPaused = false
    var taggingProgress: Double = 0.0

    // Refine queue state
    var refineQueue: [RefineFile] = []
    var selectedRefineFile: RefineFile?

    // Services
    let bookmarkManager = BookmarkManager()
    let audioPlayer = AudioPlayer()
    private(set) var taggingEngine: TaggingEngine?
    private let modelManager = ModelManager()

    // MARK: - Secure Credentials

    /// Get the Anthropic API key from Keychain
    var anthropicAPIKey: String? {
        KeychainManager.shared.retrieve(key: .anthropicAPIKey)
    }

    /// Set the Anthropic API key in Keychain
    func setAnthropicAPIKey(_ key: String?) throws {
        let normalized = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalized.isEmpty {
            try KeychainManager.shared.save(normalized, for: .anthropicAPIKey)
        } else {
            try KeychainManager.shared.delete(key: .anthropicAPIKey)
        }
    }

    /// Check if API key is configured
    var hasAnthropicAPIKey: Bool {
        canUseAnthropicAPI
    }

    /// True only when the app can retrieve a non-empty Anthropic key right now.
    var canUseAnthropicAPI: Bool {
        KeychainManager.shared.retrieve(key: .anthropicAPIKey) != nil
    }

    /// AI descriptions are not allowed to remain enabled without key access.
    func setAIDescriptionsEnabled(_ enabled: Bool) {
        taggingPreferences.aiDescriptions.enabled = enabled && canUseAnthropicAPI
    }

    func disableAIDescriptionsIfKeyUnavailable() {
        if !canUseAnthropicAPI {
            taggingPreferences.aiDescriptions.enabled = false
        }
    }

    // MARK: - Model Loading

    /// Load a trained model from a directory
    /// - Parameters:
    ///   - modelDirectory: Directory containing .mlmodel files and metadata JSON
    ///   - modelName: Optional model name for locating metadata file (defaults to directory name)
    @MainActor
    func loadModel(from modelDirectory: URL, modelName: String? = nil) async throws {
        // Set loading state
        isLoadingModel = true
        modelLoadingProgress = 0.0

        defer {
            isLoadingModel = false
        }

        // Initialize tagging engine if needed
        if taggingEngine == nil {
            taggingEngine = try TaggingEngine()
        }

        guard let engine = taggingEngine else {
            throw NSError(domain: "AppState", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize tagging engine"])
        }

        // Load model with progress reporting
        let (count, name) = try await engine.loadModel(from: modelDirectory, modelName: modelName) { @MainActor [weak self] progress in
            self?.modelLoadingProgress = progress
        }

        // Sync fallback config and strictness offset to engine
        await engine.setFallbackConfig(fallbackMappingConfig)
        await engine.setStrictnessOffset(taggingPreferences.strictness.offset)

        // Update state on main actor
        modelLoaded = true
        self.modelName = name
        loadedTagNames = await engine.loadedTags

        // Save as default model (copy into Application Support if needed)
        var pathToPersist = modelDirectory.path
        do {
            let modelsDir = try await modelManager.modelsDirectory()
            let modelsRoot = modelsDir.standardizedFileURL.path
            let modelPath = modelDirectory.standardizedFileURL.path
            if !modelPath.hasPrefix(modelsRoot + "/") {
                let destURL = modelsDir.appendingPathComponent(modelDirectory.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.copyItem(at: modelDirectory, to: destURL)
                }
                pathToPersist = destURL.path
            }
        } catch {
            logger.error("Failed to copy model into default location: \(error.localizedDescription)")
        }

        UserDefaults.standard.set(pathToPersist, forKey: "lastLoadedModelPath")
        do {
            try await modelManager.saveDefaultModelPath(pathToPersist)
        } catch {
            logger.error("Failed to persist default model path: \(error.localizedDescription)")
        }
        await modelManager.setDefaultModel(name: URL(fileURLWithPath: pathToPersist).lastPathComponent)

        logger.info("Loaded model '\(name)' with \(count) classifiers: \(self.loadedTagNames)")
    }

    /// Load the default/bundled model on app startup
    @MainActor
    func loadDefaultModel() async {
        // Try loading last used model
        if let lastPath = UserDefaults.standard.string(forKey: "lastLoadedModelPath") {
            let url = URL(fileURLWithPath: lastPath)
            if FileManager.default.fileExists(atPath: lastPath) {
                do {
                    try await loadModel(from: url)
                    return
                } catch {
                    logger.warning("Failed to load last model: \(error.localizedDescription)")
                }
            }
        }
        if let fallbackPath = await modelManager.loadDefaultModelPath() {
            let url = URL(fileURLWithPath: fallbackPath)
            if FileManager.default.fileExists(atPath: fallbackPath) {
                do {
                    try await loadModel(from: url)
                    return
                } catch {
                    logger.warning("Failed to load persisted default model: \(error.localizedDescription)")
                }
            }
        }

        // Try most recently trained model in default models directory
        if let latestModelDir = await modelManager.latestTrainedModelDirectory() {
            do {
                try await loadModel(from: latestModelDir)
                return
            } catch {
                logger.warning("Failed to load latest trained model: \(error.localizedDescription)")
            }
        }

        // Try loading bundled model from app resources
        if let bundledModelURL = Bundle.main.url(forResource: "DefaultModel", withExtension: nil, subdirectory: "Models") {
            do {
                try await loadModel(from: bundledModelURL)
                return
            } catch {
                logger.warning("Failed to load bundled model: \(error.localizedDescription)")
            }
        }

        // Try finding any available model in Application Support
        do {
            let modelsDir = try await modelManager.modelsDirectory()
            let contents = try FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)
            let modelDirs = contents.filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }

            if let firstModel = modelDirs.first {
                try await loadModel(from: firstModel)
            }
        } catch {
            logger.info("No models available: \(error.localizedDescription)")
        }
    }

    /// Unload current model
    @MainActor
    func unloadModel() async {
        await taggingEngine?.unloadUserModel()
        modelLoaded = false
        modelName = nil
        loadedTagNames = []
    }

    // MARK: - Fallback Mappings

    /// Save and sync fallback mapping configuration
    @MainActor
    func saveFallbackMappings() async {
        FallbackMappingManager().save(fallbackMappingConfig)
        await taggingEngine?.setFallbackConfig(fallbackMappingConfig)
    }

    /// Sync tagging preferences to engine (call before tagging)
    @MainActor
    func syncTaggingPreferences() async {
        await taggingEngine?.setStrictnessOffset(taggingPreferences.strictness.offset)
    }

    // Toasts
    var toast: Toast?

    enum AppView: String, CaseIterable {
        case tagging
        case train
        case refine

        var displayName: String {
            switch self {
            case .tagging: return "Tag"
            case .train: return "Train"
            case .refine: return "Refine"
            }
        }
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

        /// Security-scoped bookmark data for file access
        var bookmarkData: Data?

        /// Whether security-scoped access is currently active for this file
        var securityAccessActive: Bool = false

        /// Tags written to the file (populated after successful tagging)
        var writtenTags: WrittenTags?

        enum Status { case pending, processing, complete, error }

        var fileName: String { url.lastPathComponent }

        /// Create a QueuedFile and optionally start security-scoped access immediately
        /// - Parameters:
        ///   - url: The file URL (should be from NSOpenPanel for security scope)
        ///   - startAccessImmediately: If true, starts security-scoped access now
        init(url: URL, startAccessImmediately: Bool = false, status: Status = .pending, error: String? = nil) {
            self.url = url
            self.status = status
            self.error = error

            if startAccessImmediately {
                // Start security-scoped access immediately while NSOpenPanel's grant is active
                self.securityAccessActive = url.startAccessingSecurityScopedResource()
                let accessActive = self.securityAccessActive
                let filePath = url.path
                logger.debug("QueuedFile startAccessImmediately: \(accessActive) for \(filePath)")

                // Create bookmark while we have access
                if self.securityAccessActive {
                    self.bookmarkData = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
            }
        }

        /// Start security-scoped access for this file (call before file operations)
        mutating func startAccess() -> Bool {
            if securityAccessActive {
                return true
            }

            // Try resolving from bookmark
            if let bookmarkData = bookmarkData {
                var isStale = false
                if let resolvedURL = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    let started = resolvedURL.startAccessingSecurityScopedResource()
                    let filePath = url.path
                    logger.debug("QueuedFile startAccess (bookmark): \(started) for \(filePath)")
                    if started {
                        securityAccessActive = true
                        return true
                    }
                }
            }

            // Try direct access
            let started = url.startAccessingSecurityScopedResource()
            let filePath = url.path
            logger.debug("QueuedFile startAccess (direct): \(started) for \(filePath)")
            if started {
                securityAccessActive = true
                return true
            }

            return false
        }

        /// Stop security-scoped access for this file
        mutating func stopAccess() {
            if securityAccessActive {
                url.stopAccessingSecurityScopedResource()
                securityAccessActive = false
            }
        }

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
        var essentiaSubGenre: String?
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

/// How strict the tagging threshold should be.
/// Each level is an OFFSET applied to the engine's per-category default
/// thresholds (Genre 0.70, Mood/Descriptive/Timing 0.55), so the category
/// structure survives every strictness level instead of collapsing into one
/// absolute number. Tuned per-tag thresholds always win.
enum TaggingStrictness: String, Codable, CaseIterable {
    case loose = "loose"        // category defaults − 0.15
    case average = "average"    // category defaults as-is
    case strict = "strict"      // category defaults + 0.15
    case veryStrict = "veryStrict" // category defaults + 0.25

    var offset: Float {
        switch self {
        case .loose: return -0.15
        case .average: return 0.0
        case .strict: return 0.15
        case .veryStrict: return 0.25
        }
    }

    var displayName: String {
        switch self {
        case .loose: return "Loose (−15%)"
        case .average: return "Balanced (category defaults)"
        case .strict: return "Strict (+15%)"
        case .veryStrict: return "Very Strict (+25%)"
        }
    }

    var description: String {
        switch self {
        case .loose: return "More tags, may include uncertain matches"
        case .average: return "Per-category default thresholds — balanced precision and recall"
        case .strict: return "Fewer tags, higher confidence"
        case .veryStrict: return "Only very confident predictions"
        }
    }
}

struct TaggingPreferences: Codable {
    var genre = FieldPreference(enabled: true, targetField: "TCON")
    var subGenre = FieldPreference(enabled: false, targetField: "TXXX:CRATEBOT_SUBGENRE")
    var album = FieldPreference(enabled: true, targetField: "TALB")
    var mood = FieldPreference(enabled: true, targetField: "TIT1")
    var comments = FieldPreference(enabled: true, targetField: "COMM")
    var likeness = FieldPreference(enabled: true, targetField: "TIT1")
    var vibesShort = FieldPreference(enabled: false, targetField: "TXXX:CRATEBOT_VIBE_SHORT")
    var vibesLong = FieldPreference(enabled: false, targetField: "COMM")
    var aiDescriptions = FieldPreference(enabled: false, targetField: "TCOM/TIT3/MVNM")
    var hooks = FieldPreference(enabled: false, targetField: "TXXX:CRATEBOT_HOOK")
    var overwrite = true
    var strictness: TaggingStrictness = .average

    struct FieldPreference: Codable {
        var enabled: Bool
        var targetField: String
    }

    // Legacy support for migration
    private enum CodingKeys: String, CodingKey {
        case genre, subGenre, album, mood, comments, likeness, vibesShort, vibesLong, aiDescriptions, hooks, overwrite, strictness
        case vibes // Legacy key
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        genre = try container.decodeIfPresent(FieldPreference.self, forKey: .genre) ?? FieldPreference(enabled: true, targetField: "TCON")
        subGenre = try container.decodeIfPresent(FieldPreference.self, forKey: .subGenre) ?? FieldPreference(enabled: false, targetField: "TXXX:CRATEBOT_SUBGENRE")
        album = try container.decodeIfPresent(FieldPreference.self, forKey: .album) ?? FieldPreference(enabled: true, targetField: "TALB")
        mood = try container.decodeIfPresent(FieldPreference.self, forKey: .mood) ?? FieldPreference(enabled: true, targetField: "TIT1")
        comments = try container.decodeIfPresent(FieldPreference.self, forKey: .comments) ?? FieldPreference(enabled: true, targetField: "COMM")
        likeness = try container.decodeIfPresent(FieldPreference.self, forKey: .likeness) ?? FieldPreference(enabled: true, targetField: "TIT1")
        hooks = try container.decodeIfPresent(FieldPreference.self, forKey: .hooks) ?? FieldPreference(enabled: false, targetField: "TXXX:CRATEBOT_HOOK")
        overwrite = try container.decodeIfPresent(Bool.self, forKey: .overwrite) ?? true
        strictness = try container.decodeIfPresent(TaggingStrictness.self, forKey: .strictness) ?? .average
        aiDescriptions = try container.decodeIfPresent(FieldPreference.self, forKey: .aiDescriptions) ?? FieldPreference(enabled: false, targetField: "TCOM/TIT3/MVNM")
        if aiDescriptions.targetField == "TCOM" {
            aiDescriptions.targetField = "TCOM/TIT3/MVNM"
        }

        // Try new keys first, fall back to legacy vibes structure
        if let short = try? container.decodeIfPresent(FieldPreference.self, forKey: .vibesShort),
           let long = try? container.decodeIfPresent(FieldPreference.self, forKey: .vibesLong) {
            vibesShort = short
            vibesLong = long
        } else if let legacyVibes = try? container.decodeIfPresent(LegacyVibesPreference.self, forKey: .vibes) {
            vibesShort = FieldPreference(enabled: legacyVibes.enabled, targetField: legacyVibes.shortTargetField)
            vibesLong = FieldPreference(enabled: legacyVibes.enabled, targetField: legacyVibes.longTargetField)
        } else {
            vibesShort = FieldPreference(enabled: false, targetField: "TXXX:CRATEBOT_VIBE_SHORT")
            vibesLong = FieldPreference(enabled: false, targetField: "COMM")
        }
    }

    private struct LegacyVibesPreference: Codable {
        var enabled: Bool
        var shortTargetField: String
        var longTargetField: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(genre, forKey: .genre)
        try container.encode(subGenre, forKey: .subGenre)
        try container.encode(album, forKey: .album)
        try container.encode(mood, forKey: .mood)
        try container.encode(comments, forKey: .comments)
        try container.encode(likeness, forKey: .likeness)
        try container.encode(vibesShort, forKey: .vibesShort)
        try container.encode(vibesLong, forKey: .vibesLong)
        try container.encode(aiDescriptions, forKey: .aiDescriptions)
        try container.encode(hooks, forKey: .hooks)
        try container.encode(overwrite, forKey: .overwrite)
        try container.encode(strictness, forKey: .strictness)
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
