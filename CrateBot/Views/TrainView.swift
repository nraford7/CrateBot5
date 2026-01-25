import SwiftUI
import CrateBotCore
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - ID3 Field Configuration

/// Available ID3 fields that can be mapped to training categories
/// Names match iTunes/Apple Music column names for user familiarity
enum ID3Field: String, CaseIterable, Identifiable, Codable {
    // Primary tagging fields (most useful for CrateBot)
    case genre = "Genre"
    case grouping = "Grouping"
    case comments = "Comments"
    case album = "Album"
    case composer = "Composer"
    case trackDescription = "Description"

    // Track metadata (visible in iTunes)
    case artist = "Artist"
    case albumArtist = "Album Artist"
    case bpm = "Beats Per Minute"
    case category = "Category"
    case movementName = "Movement Name"
    case work = "Work"

    var id: String { rawValue }

    var shortName: String { rawValue }

    var iTunesDescription: String {
        switch self {
        case .genre: return "Main genre classification"
        case .grouping: return "Content grouping for organization"
        case .comments: return "Free-form comments field"
        case .album: return "Album name"
        case .composer: return "Composer/writer credits"
        case .trackDescription: return "Track description/subtitle"
        case .artist: return "Primary artist"
        case .albumArtist: return "Album artist (compilation support)"
        case .bpm: return "Tempo in beats per minute"
        case .category: return "iTunes category field"
        case .movementName: return "Classical movement name"
        case .work: return "Work/composition name"
        }
    }

    /// Convert to CrateBotCore's ID3FieldType (for training data collection)
    var coreFieldType: TrainingDataCollector.ID3FieldType? {
        switch self {
        case .artist: return .artist
        case .albumArtist: return .albumArtist
        case .album: return .album
        case .genre: return .genre
        case .grouping: return .contentGroup
        case .comments: return .comments
        case .composer: return .composer
        case .trackDescription: return .subtitle
        case .bpm: return .bpm
        case .category, .movementName, .work: return nil
        }
    }

    /// The ID3v2.3 frame identifier
    var frameID: String {
        switch self {
        case .genre: return "TCON"
        case .grouping: return "TIT1"
        case .comments: return "COMM"
        case .album: return "TALB"
        case .composer: return "TCOM"
        case .trackDescription: return "TIT3"
        case .artist: return "TPE1"
        case .albumArtist: return "TPE2"
        case .bpm: return "TBPM"
        case .category: return "TCAT"           // iTunes Category
        case .movementName: return "MVNM"       // iTunes Movement Name
        case .work: return "TXXX:WORK"          // iTunes Work field
        }
    }

    /// Create from a frame ID
    static func from(frameID: String) -> ID3Field? {
        allCases.first { $0.frameID == frameID }
    }

    /// Get display name from frame ID (for custom TXXX fields)
    static func displayName(for frameID: String) -> String {
        if let field = from(frameID: frameID) {
            return field.shortName
        }
        // Handle TXXX custom fields
        if frameID.hasPrefix("TXXX:") {
            let customName = frameID.replacingOccurrences(of: "TXXX:", with: "")
            return "Custom: \(customName)"
        }
        return frameID
    }
}

/// Configuration for mapping ID3 fields to training categories
struct TagMappingConfiguration: Equatable, Codable {
    var genreField: ID3Field = .genre
    var timingField: ID3Field = .album
    var moodField: ID3Field = .grouping
    var descriptiveField: ID3Field = .comments

    static let `default` = TagMappingConfiguration()

    var coreMapping: TrainingDataCollector.TagFieldMapping {
        .init(
            genreField: genreField.coreFieldType ?? .genre,
            timingField: timingField.coreFieldType ?? .album,
            moodField: moodField.coreFieldType ?? .contentGroup,
            descriptiveField: descriptiveField.coreFieldType ?? .comments
        )
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "CrateBot.TagMappingConfiguration"

    /// Save to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    /// Load from UserDefaults
    static func load() -> TagMappingConfiguration {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(TagMappingConfiguration.self, from: data) else {
            return .default
        }
        return config
    }
}

/// Discovered tags organized by category
struct DiscoveredTags: Equatable {
    var genre: [String: Int] = [:]
    var timing: [String: Int] = [:]
    var mood: [String: Int] = [:]
    var descriptive: [String: Int] = [:]
    var totalFiles: Int = 0
}

/// Selected tags for training
struct SelectedTrainingTags: Equatable, Codable {
    var genre: Set<String> = []
    var timing: Set<String> = []
    var mood: Set<String> = []
    var descriptive: Set<String> = []

    var allTags: Set<String> {
        genre.union(timing).union(mood).union(descriptive)
    }

    var isEmpty: Bool {
        genre.isEmpty && timing.isEmpty && mood.isEmpty && descriptive.isEmpty
    }

    var totalCount: Int {
        genre.count + timing.count + mood.count + descriptive.count
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "CrateBot.SelectedTrainingTags"

    /// Save to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    /// Load from UserDefaults
    static func load() -> SelectedTrainingTags {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let tags = try? JSONDecoder().decode(SelectedTrainingTags.self, from: data) else {
            return SelectedTrainingTags()
        }
        return tags
    }
}

// MARK: - Training View Model

/// Persists training state across tab switches
@MainActor
final class TrainingViewModel: ObservableObject {
    // Training state
    @Published var selectedFolders: [URL] = []
    @Published var modelName: String = UserDefaults.standard.string(forKey: "CrateBot.LastModelName") ?? "" {
        didSet { UserDefaults.standard.set(modelName, forKey: "CrateBot.LastModelName") }
    }
    @Published var trainingState: TrainingCoordinator.State = .idle
    @Published var trainingSummary: TrainingCoordinator.TrainingSummary?

    // Configuration state
    @Published var tagMapping = TagMappingConfiguration.load() {
        didSet { tagMapping.save() }
    }
    @Published var discoveredTags: DiscoveredTags?
    @Published var selectedTags = SelectedTrainingTags.load() {
        didSet { selectedTags.save() }
    }

    // Training control
    @Published var trainingStartTime: Date?
    @Published var isPaused: Bool = false
    @Published var isCancelled: Bool = false
    var trainingTask: Task<Void, Never>?

    // Dependencies
    let coordinator = TrainingCoordinator()
    let minSamplesPerTag = 50

    // Singleton for persistence across tab switches
    static let shared = TrainingViewModel()

    private init() {}

    func startTraining() {
        let trimmedName = modelName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !selectedTags.isEmpty else { return }

        // Reset progress state
        trainingStartTime = Date()
        isPaused = false
        isCancelled = false

        let options = TrainingCoordinator.TrainingOptions(
            modelName: trimmedName,
            selectedTags: selectedTags.allTags,
            validationSplit: 0.2,
            minSamplesPerTag: minSamplesPerTag,
            tagFieldMapping: tagMapping.coreMapping
        )

        trainingTask = Task {
            do {
                let summary = try await coordinator.train(
                    from: selectedFolders,
                    options: options
                ) { [weak self] state in
                    Task { @MainActor [weak self] in
                        guard let self = self, !self.isCancelled else { return }
                        self.trainingState = state
                    }
                }

                if !isCancelled {
                    trainingSummary = summary
                }
            } catch {
                if !isCancelled {
                    trainingState = .failed(error: error.localizedDescription)
                }
            }
        }
    }

    func cancelTraining() {
        isCancelled = true
        trainingTask?.cancel()
        trainingState = .failed(error: "Training cancelled by user")
    }

    func resetState() {
        selectedFolders = []
        // Keep model name - it's persisted
        trainingState = .idle
        trainingSummary = nil
        discoveredTags = nil
        trainingStartTime = nil
        isPaused = false
        isCancelled = false
        trainingTask = nil

        Task {
            await coordinator.reset()
        }
    }

    /// Get current pipeline step index based on training state
    var currentPipelineStep: Int {
        switch trainingState {
        case .idle: return 0
        case .collecting: return 1
        case .extractingFeatures: return 1
        case .training: return 2
        case .packaging: return 3
        case .complete: return 4
        case .failed: return -1
        }
    }
}

// MARK: - TrainView

struct TrainView: View {
    // Use shared view model that persists across tab switches
    @StateObject private var viewModel = TrainingViewModel.shared
    @Environment(AppState.self) private var appState

    // Sheet state (local to view)
    @State private var showTagSelectionSheet = false

    // MARK: - Body

    var body: some View {
        Group {
            switch viewModel.trainingState {
            case .idle:
                folderSelectionView
            case .collecting(let progress):
                detailedProgressView(
                    phase: "Collecting Training Data",
                    detailedProgress: progress,
                    currentTag: nil,
                    showFeatureInfo: false
                )
            case .extractingFeatures(let progress):
                detailedProgressView(
                    phase: "Extracting Features",
                    detailedProgress: progress,
                    currentTag: nil,
                    showFeatureInfo: true
                )
            case .training(let progress, let currentTag):
                detailedProgressView(
                    phase: "Training Models",
                    detailedProgress: TrainingCoordinator.DetailedProgress(
                        processed: Int(progress * Double(viewModel.selectedTags.totalCount)),
                        total: viewModel.selectedTags.totalCount,
                        currentFile: nil
                    ),
                    currentTag: currentTag,
                    showFeatureInfo: false
                )
            case .packaging:
                packagingView
            case .complete(let modelName):
                completeView(modelName: modelName)
            case .failed(let error):
                failedView(error: error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.bgWindow)
        .sheet(isPresented: $showTagSelectionSheet) {
            TagSelectionSheet(
                directories: viewModel.selectedFolders,
                tagMapping: $viewModel.tagMapping,
                discoveredTags: $viewModel.discoveredTags,
                selectedTags: $viewModel.selectedTags,
                modelName: $viewModel.modelName,
                onStartTraining: { viewModel.startTraining() }
            )
        }
        .onChange(of: viewModel.trainingSummary?.modelName) { _, newValue in
            // Load the trained model after training completes
            if let summary = viewModel.trainingSummary {
                Task {
                    do {
                        try await appState.loadModel(from: summary.modelURL)
                        appState.showToast("Model '\(summary.modelName)' loaded", kind: .success)
                    } catch {
                        print("Failed to load trained model: \(error)")
                        appState.showToast("Failed to load model: \(error.localizedDescription)", kind: .error)
                    }
                }
            }
        }
    }

    // MARK: - Folder Selection View

    private var folderSelectionView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(Theme.Colors.textTertiary)

            Text("Select Training Data")
                .font(Theme.Fonts.heading(24))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Choose folders containing your tagged MP3 files")
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textSecondary)

            if !viewModel.selectedFolders.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.selectedFolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.Colors.accentPrimary)
                            Text(folder.lastPathComponent)
                                .font(Theme.Fonts.mono(13))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                viewModel.selectedFolders.removeAll { $0 == folder }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                }
                .frame(maxWidth: 400)
                .padding(.vertical)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    selectFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }
                .buttonStyle(viewModel.selectedFolders.isEmpty ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))

                Button {
                    showTagSelectionSheet = true
                } label: {
                    Label("Configure & Scan", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(viewModel.selectedFolders.isEmpty ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
                .disabled(viewModel.selectedFolders.isEmpty)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Progress Views

    private func detailedProgressView(
        phase: String,
        detailedProgress: TrainingCoordinator.DetailedProgress,
        currentTag: String?,
        showFeatureInfo: Bool
    ) -> some View {
        let progress = detailedProgress.fraction

        return VStack(spacing: Theme.Spacing.md) {
            // Pipeline stepper
            PipelineStepper(
                steps: ["Select Files", "Extract Features", "Train Model", "Validate"],
                currentStep: viewModel.currentPipelineStep
            )

            // Active processing card
            ThemedCard(accentColor: Theme.Colors.statusWarning) {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: 6) {
                            if viewModel.isPaused {
                                Image(systemName: "pause.circle.fill")
                                    .foregroundStyle(Theme.Colors.statusWarning)
                            } else {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(Theme.Colors.statusWarning)
                            }
                            Text(viewModel.isPaused ? "PAUSED" : "PROCESSING")
                                .font(Theme.Fonts.label(10))
                                .foregroundColor(Theme.Colors.statusWarning)
                                .tracking(0.5)
                        }

                        if let tag = currentTag {
                            Text("Training: \(tag)")
                                .font(Theme.Fonts.mono(14))
                                .fontWeight(.medium)
                                .foregroundColor(Theme.Colors.textPrimary)
                        } else if let currentFile = detailedProgress.currentFile {
                            Text(currentFile)
                                .font(Theme.Fonts.mono(14))
                                .fontWeight(.medium)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(phase)
                                .font(Theme.Fonts.mono(14))
                                .fontWeight(.medium)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }

                        if showFeatureInfo {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.Colors.accentPrimary)
                                    .frame(width: 6, height: 6)
                                Text("Discogs-EffNet (1280-dim)")
                                    .font(Theme.Fonts.body(12))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: Theme.Spacing.sm) {
                        if viewModel.isPaused {
                            Button("Resume") {
                                viewModel.isPaused = false
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        } else {
                            Button("Pause") {
                                viewModel.isPaused = true
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        Button("Stop") {
                            viewModel.cancelTraining()
                        }
                        .buttonStyle(DangerButtonStyle())
                    }
                }

                // Progress bar
                VStack(alignment: .leading, spacing: 4) {
                    ThemedProgressBar(progress: progress)

                    HStack {
                        Text("Feature extraction progress")
                            .font(Theme.Fonts.body(12))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text("\(detailedProgress.processed) of \(detailedProgress.total) files (\(Int(progress * 100))%)")
                            .font(Theme.Fonts.mono(12))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }

            // Stats row
            HStack(spacing: Theme.Spacing.sm) {
                StatCard(
                    label: "Completed",
                    value: "\(detailedProgress.processed)",
                    detail: "\(detailedProgress.total - detailedProgress.processed) remaining"
                )
                StatCard(
                    label: "Tags",
                    value: "\(viewModel.selectedTags.totalCount)",
                    detail: "selected for training"
                )
                StatCard(
                    label: "Speed",
                    value: calculateAverageTime(processed: detailedProgress.processed),
                    detail: "per file avg"
                )
                StatCard(
                    label: "Time Remaining",
                    value: calculateETA(processed: detailedProgress.processed, total: detailedProgress.total),
                    detail: "at current rate",
                    isHighlighted: true
                )
            }

            // File list
            VStack(spacing: 0) {
                // Header
                ThemedSectionHeader(title: "Files", count: detailedProgress.total)

                // List
                if detailedProgress.allFiles.isEmpty {
                    VStack {
                        Text("Waiting for files...")
                            .font(Theme.Fonts.body(14))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(Theme.Colors.bgSurface)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(detailedProgress.allFiles.enumerated()), id: \.offset) { index, fileName in
                                    ThemedFileRow(
                                        filename: fileName,
                                        artist: nil,
                                        duration: nil,
                                        status: fileStatus(for: index, progress: detailedProgress),
                                        time: nil
                                    )
                                    .id(index)

                                    if index < detailedProgress.allFiles.count - 1 {
                                        Divider()
                                            .background(Theme.Colors.textTertiary.opacity(0.1))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 300)
                        .onChange(of: detailedProgress.processed) { _, newValue in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(max(0, newValue - 2), anchor: .top)
                            }
                        }
                    }
                    .background(Theme.Colors.bgSurface)
                }
            }
            .cornerRadius(Theme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.Colors.textTertiary.opacity(0.1), lineWidth: 1)
            )
        }
        .padding()
        .onAppear {
            if viewModel.trainingStartTime == nil {
                viewModel.trainingStartTime = Date()
            }
        }
    }

    /// Determine status for a file based on its index and progress
    private func fileStatus(for index: Int, progress: TrainingCoordinator.DetailedProgress) -> StatusLED.Status {
        if index < progress.processed {
            return .complete
        } else if index == progress.processed {
            return .processing
        } else {
            return .pending
        }
    }

    // Time calculation methods
    private func calculateAverageTime(processed: Int) -> String {
        guard processed > 0, let startTime = viewModel.trainingStartTime else { return "-" }
        let elapsed = Date().timeIntervalSince(startTime)
        let avg = elapsed / Double(processed)
        return String(format: "%.1fs", avg)
    }

    private func calculateETA(processed: Int, total: Int) -> String {
        guard processed > 0, let startTime = viewModel.trainingStartTime else { return "-" }
        let elapsed = Date().timeIntervalSince(startTime)
        let avgPerFile = elapsed / Double(processed)
        let remaining = Double(total - processed) * avgPerFile
        return formatDuration(remaining)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }

    private var packagingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.Colors.accentPrimary)

            Text("Packaging Model...")
                .font(Theme.Fonts.heading(20))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Creating model bundle and metadata")
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Complete View

    private func completeView(modelName: String) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Success header
                VStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.statusSuccess.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.Colors.statusSuccess)
                    }

                    Text("Training Complete!")
                        .font(Theme.Fonts.heading(24))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("Model: \(modelName)")
                        .font(Theme.Fonts.mono(16))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.top, Theme.Spacing.lg)

                if let summary = viewModel.trainingSummary {
                    // Summary stats
                    HStack(spacing: Theme.Spacing.md) {
                        summaryStatCard(
                            title: "Trained Tags",
                            value: "\(summary.tagResults.count)",
                            color: Theme.Colors.statusSuccess
                        )
                        summaryStatCard(
                            title: "Avg Accuracy",
                            value: String(format: "%.1f%%", summary.averageAccuracy * 100),
                            color: Theme.Colors.accentPrimary
                        )
                        summaryStatCard(
                            title: "Tracks Used",
                            value: "\(summary.tracksUsedForTraining)",
                            color: Theme.Colors.textSecondary
                        )
                        if summary.tracksWithInvalidFeatures > 0 {
                            summaryStatCard(
                                title: "Invalid Tracks",
                                value: "\(summary.tracksWithInvalidFeatures)",
                                color: Theme.Colors.statusWarning
                            )
                        }
                    }
                    .frame(maxWidth: 600)

                    // Trained tags section
                    if !summary.tagResults.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.statusSuccess)
                                Text("Trained Tags (\(summary.tagResults.count))")
                                    .font(Theme.Fonts.heading(16))
                                    .foregroundColor(Theme.Colors.textPrimary)
                            }

                            VStack(spacing: 1) {
                                // Header row
                                HStack {
                                    Text("Tag")
                                        .frame(width: 150, alignment: .leading)
                                    Text("Samples")
                                        .frame(width: 80, alignment: .trailing)
                                    Text("Train Acc")
                                        .frame(width: 80, alignment: .trailing)
                                    Text("Val Acc")
                                        .frame(width: 80, alignment: .trailing)
                                }
                                .font(Theme.Fonts.label(11))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.Colors.bgElevated)

                                // Tag rows
                                ForEach(summary.tagResults.sorted(by: { $0.validationAccuracy > $1.validationAccuracy }), id: \.tag) { result in
                                    trainedTagRow(result)
                                }
                            }
                            .background(Theme.Colors.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .strokeBorder(Theme.Colors.textTertiary.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .frame(maxWidth: 500)
                    }

                    // Skipped tags section
                    if !summary.skippedTagDetails.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.statusWarning)
                                Text("Skipped Tags (\(summary.skippedTagDetails.count))")
                                    .font(Theme.Fonts.heading(16))
                                    .foregroundColor(Theme.Colors.textPrimary)
                            }

                            VStack(spacing: 1) {
                                ForEach(summary.skippedTagDetails.sorted(by: { $0.sampleCount > $1.sampleCount }), id: \.tag) { skipped in
                                    skippedTagRow(skipped)
                                }
                            }
                            .background(Theme.Colors.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .strokeBorder(Theme.Colors.textTertiary.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .frame(maxWidth: 500)
                    }

                    // Track stats note
                    if summary.tracksWithInvalidFeatures > 0 {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Theme.Colors.statusWarning)
                            Text("\(summary.tracksWithInvalidFeatures) tracks had invalid audio features (NaN/Inf) and were excluded from training.")
                                .font(Theme.Fonts.body(12))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.statusWarning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .frame(maxWidth: 500)
                    }
                }

                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        viewModel.resetState()
                    } label: {
                        Label("Train Another", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if let summary = viewModel.trainingSummary {
                        Button {
                            exportTrainingStatus(summary)
                        } label: {
                            Label("Export Status", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Button {
                        viewModel.resetState()
                        appState.currentView = .tagging
                    } label: {
                        Label("Let's Tag Some Tracks", systemImage: "tag")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private func summaryStatCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(Theme.Fonts.mono(24))
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(title)
                .font(Theme.Fonts.label(11))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func trainedTagRow(_ result: TrainingCoordinator.TagTrainingResult) -> some View {
        HStack {
            Text(result.tag)
                .font(Theme.Fonts.body(13))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text("\(result.positiveCount)")
                .font(Theme.Fonts.mono(12))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 80, alignment: .trailing)

            Text(String(format: "%.1f%%", result.trainingAccuracy * 100))
                .font(Theme.Fonts.mono(12))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 80, alignment: .trailing)

            Text(String(format: "%.1f%%", result.validationAccuracy * 100))
                .font(Theme.Fonts.mono(12))
                .fontWeight(.medium)
                .foregroundColor(accuracyColor(result.validationAccuracy))
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.bgSurface)
    }

    private func skippedTagRow(_ skipped: TrainingCoordinator.SkippedTag) -> some View {
        HStack {
            Text(skipped.tag)
                .font(Theme.Fonts.body(13))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text("\(skipped.sampleCount) samples")
                .font(Theme.Fonts.mono(12))
                .foregroundColor(Theme.Colors.textTertiary)

            Text(skipped.reason.description)
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.statusWarning)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.bgSurface)
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.8 {
            return Theme.Colors.statusSuccess
        } else if accuracy >= 0.6 {
            return Theme.Colors.statusWarning
        } else {
            return Theme.Colors.statusError
        }
    }

    // MARK: - Failed View

    private func failedView(error: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.Colors.statusError.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Colors.statusError)
            }

            Text("Training Failed")
                .font(Theme.Fonts.heading(24))
                .foregroundColor(Theme.Colors.textPrimary)

            Text(error)
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button {
                viewModel.resetState()
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top)

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                if !viewModel.selectedFolders.contains(url) {
                    viewModel.selectedFolders.append(url)
                }
            }
        }
    }

    private func exportTrainingStatus(_ summary: TrainingCoordinator.TrainingSummary) {
        let report = generateTrainingReport(summary)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(summary.modelName)_training_report.txt"
        panel.title = "Export Training Status"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                appState.showToast("Report exported successfully", kind: .success)
            } catch {
                appState.showToast("Failed to export: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    private func generateTrainingReport(_ summary: TrainingCoordinator.TrainingSummary) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .medium

        var report = """
        ================================================================================
        CRATEBOT TRAINING REPORT
        ================================================================================

        Model Name:       \(summary.modelName)
        Generated:        \(dateFormatter.string(from: Date()))
        Model Location:   \(summary.modelURL.path)

        --------------------------------------------------------------------------------
        SUMMARY
        --------------------------------------------------------------------------------

        Total Tracks Scanned:      \(summary.totalTracksScanned)
        Tracks Used for Training:  \(summary.tracksUsedForTraining)
        Tracks with Invalid Data:  \(summary.tracksWithInvalidFeatures)

        Tags Trained:              \(summary.tagResults.count)
        Tags Skipped:              \(summary.skippedTagDetails.count)

        Average Validation Accuracy: \(String(format: "%.1f%%", summary.averageAccuracy * 100))

        """

        if !summary.tagResults.isEmpty {
            report += """

        --------------------------------------------------------------------------------
        TRAINED TAGS
        --------------------------------------------------------------------------------

        """
            let sortedResults = summary.tagResults.sorted { $0.validationAccuracy > $1.validationAccuracy }

            // Header
            report += String(format: "%-30s %10s %12s %12s\n", "Tag", "Samples", "Train Acc", "Val Acc")
            report += String(repeating: "-", count: 66) + "\n"

            for result in sortedResults {
                let tag = result.tag.count > 28 ? String(result.tag.prefix(28)) + ".." : result.tag
                report += String(format: "%-30s %10d %11.1f%% %11.1f%%\n",
                    tag,
                    result.positiveCount,
                    result.trainingAccuracy * 100,
                    result.validationAccuracy * 100
                )
            }
        }

        if !summary.skippedTagDetails.isEmpty {
            report += """

        --------------------------------------------------------------------------------
        SKIPPED TAGS
        --------------------------------------------------------------------------------

        """
            let sortedSkipped = summary.skippedTagDetails.sorted { $0.sampleCount > $1.sampleCount }

            // Header
            report += String(format: "%-30s %10s %s\n", "Tag", "Samples", "Reason")
            report += String(repeating: "-", count: 66) + "\n"

            for skipped in sortedSkipped {
                let tag = skipped.tag.count > 28 ? String(skipped.tag.prefix(28)) + ".." : skipped.tag
                report += String(format: "%-30s %10d %s\n",
                    tag,
                    skipped.sampleCount,
                    skipped.reason.description
                )
            }
        }

        report += """

        --------------------------------------------------------------------------------
        END OF REPORT
        --------------------------------------------------------------------------------
        """

        return report
    }
}

// MARK: - Tag Selection Sheet

struct TagSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let directories: [URL]
    @Binding var tagMapping: TagMappingConfiguration
    @Binding var discoveredTags: DiscoveredTags?
    @Binding var selectedTags: SelectedTrainingTags
    @Binding var modelName: String
    let onStartTraining: () -> Void

    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var filesScanned: Int = 0
    @State private var totalFiles: Int = 0
    @State private var currentFile: String?

    private let dataCollector = TrainingDataCollector()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isScanning {
                    scanningView
                } else if let discovered = discoveredTags {
                    tagSelectionView(discovered)
                } else {
                    fieldMappingView
                }
            }
            .background(Theme.Colors.bgWindow)
            .navigationTitle("Select Training Tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                if discoveredTags != nil && !isScanning {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start Training") {
                            dismiss()
                            onStartTraining()
                        }
                        .disabled(selectedTags.isEmpty || modelName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }

    // MARK: - Field Mapping View

    private var fieldMappingView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Header
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 50))
                        .foregroundStyle(Theme.Colors.accentPrimary)

                    Text("Configure ID3 Field Mapping")
                        .font(Theme.Fonts.heading(20))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("Tell CrateBot which ID3 fields contain your Genre, Timing, Mood, and Descriptive tags.")
                        .font(Theme.Fonts.body(14))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 450)
                }
                .padding(.top, 30)

                // Field Mapping Configuration
                VStack(spacing: Theme.Spacing.md) {
                    fieldMappingRow("Genre", selection: $tagMapping.genreField, color: Theme.Colors.categoryGenre)
                    Divider().background(Theme.Colors.textTertiary.opacity(0.2))
                    fieldMappingRow("Timing", selection: $tagMapping.timingField, color: Theme.Colors.categoryTiming)
                    Divider().background(Theme.Colors.textTertiary.opacity(0.2))
                    fieldMappingRow("Mood", selection: $tagMapping.moodField, color: Theme.Colors.categoryMood)
                    Divider().background(Theme.Colors.textTertiary.opacity(0.2))
                    fieldMappingRow("Descriptive", selection: $tagMapping.descriptiveField, color: Theme.Colors.categoryDescriptive)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.bgSurface)
                .cornerRadius(Theme.Radius.md)
                .frame(maxWidth: 550)

                Button {
                    scanDirectory()
                } label: {
                    Label("Scan for Tags", systemImage: "magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top)
                .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private func fieldMappingRow(_ label: String, selection: Binding<ID3Field>, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(label)
                    .font(Theme.Fonts.label(14))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .frame(width: 120, alignment: .leading)

            Picker("", selection: selection) {
                ForEach(ID3Field.allCases) { field in
                    Text(field.shortName).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Text(selection.wrappedValue.iTunesDescription)
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            ThemedProgressBar(progress: scanProgress)
                .frame(width: 300)

            Text("Scanning for tags...")
                .font(Theme.Fonts.heading(18))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("\(filesScanned) / \(totalFiles) files")
                .font(Theme.Fonts.mono(14))
                .foregroundColor(Theme.Colors.textSecondary)

            if let file = currentFile {
                Text(file)
                    .font(Theme.Fonts.mono(12))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 400)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tag Selection View

    private func tagSelectionView(_ discovered: DiscoveredTags) -> some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button {
                    discoveredTags = nil
                    selectedTags = SelectedTrainingTags()
                } label: {
                    Label("Change Mapping", systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Text("Found \(discovered.totalFiles) files")
                    .font(Theme.Fonts.body(14))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)

            // Model name
            HStack {
                Text("Model Name:")
                    .font(Theme.Fonts.label(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                TextField("Enter model name", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }
            .padding(Theme.Spacing.md)

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            // Tag categories
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    tagSection("Genre", color: Theme.Colors.categoryGenre, tags: discovered.genre, selection: $selectedTags.genre)
                    tagSection("Timing", color: Theme.Colors.categoryTiming, tags: discovered.timing, selection: $selectedTags.timing)
                    tagSection("Mood", color: Theme.Colors.categoryMood, tags: discovered.mood, selection: $selectedTags.mood)
                    tagSection("Descriptive", color: Theme.Colors.categoryDescriptive, tags: discovered.descriptive, selection: $selectedTags.descriptive)
                }
                .padding(Theme.Spacing.md)
            }

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            // Footer
            HStack {
                Text("\(selectedTags.totalCount) tags selected")
                    .font(Theme.Fonts.body(14))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)
        }
    }

    private func tagSection(_ title: String, color: Color, tags: [String: Int], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(Theme.Fonts.heading(16))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("(\(selection.wrappedValue.count)/\(tags.count) selected)")
                    .font(Theme.Fonts.body(12))
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()

                if !tags.isEmpty {
                    Button(selection.wrappedValue.count == tags.count ? "Deselect All" : "Select All") {
                        if selection.wrappedValue.count == tags.count {
                            selection.wrappedValue = []
                        } else {
                            selection.wrappedValue = Set(tags.keys)
                        }
                    }
                    .font(Theme.Fonts.label(12))
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            if tags.isEmpty {
                Text("No tags found in this field")
                    .font(Theme.Fonts.body(14))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.vertical, Theme.Spacing.sm)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: Theme.Spacing.sm) {
                    ForEach(tags.sorted(by: { $0.value > $1.value }), id: \.key) { tag, count in
                        TagToggleButton(
                            tag: tag,
                            count: count,
                            isSelected: selection.wrappedValue.contains(tag),
                            color: color
                        ) {
                            if selection.wrappedValue.contains(tag) {
                                selection.wrappedValue.remove(tag)
                            } else {
                                selection.wrappedValue.insert(tag)
                            }
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.bgSurface)
        .cornerRadius(Theme.Radius.md)
    }

    // MARK: - Actions

    private func scanDirectory() {
        isScanning = true
        scanProgress = 0
        filesScanned = 0
        totalFiles = 0

        let mapping = tagMapping.coreMapping

        Task {
            let result = await dataCollector.discoverCategorizedTags(
                from: directories,
                mapping: mapping
            ) { progress in
                await MainActor.run {
                    self.filesScanned = progress.processed
                    self.totalFiles = progress.total
                    self.scanProgress = progress.fraction
                    if let file = progress.currentFile {
                        self.currentFile = file.lastPathComponent
                    }
                }
            }

            await MainActor.run {
                discoveredTags = DiscoveredTags(
                    genre: result.genre,
                    timing: result.timing,
                    mood: result.mood,
                    descriptive: result.descriptive,
                    totalFiles: result.totalFiles
                )
                currentFile = nil
                isScanning = false
            }
        }
    }
}

// MARK: - Tag Toggle Button

struct TagToggleButton: View {
    let tag: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? color : Theme.Colors.textTertiary)

                Text(tag)
                    .font(Theme.Fonts.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)

                Spacer()

                Text("\(count)")
                    .font(Theme.Fonts.mono(11))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? color.opacity(0.15) : Theme.Colors.bgElevated)
            .cornerRadius(Theme.Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(tag)
    }
}

#Preview {
    TrainView()
}
