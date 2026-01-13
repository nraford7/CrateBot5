import SwiftUI
import CrateBotCore
import AppKit
import Combine

// MARK: - ID3 Field Configuration

/// Available ID3 fields that can be mapped to training categories
enum ID3Field: String, CaseIterable, Identifiable, Codable {
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
        case .title: return "Song title"
        case .artist: return "Artist name"
        case .albumArtist: return "Album Artist - often repurposed"
        case .album: return "Album name"
        case .genre: return "Genre field"
        case .contentGroup: return "Grouping field"
        case .comments: return "Comments field"
        case .composer: return "Composer field"
        case .subtitle: return "Subtitle/description"
        case .conductor: return "Conductor field"
        case .lyricist: return "Lyricist field"
        case .fileOwner: return "File Owner field"
        case .bpm: return "Beats per minute"
        case .year: return "Year"
        case .publisher: return "Publisher/Label"
        case .encodedBy: return "Encoded by"
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

    var coreMapping: TrainingDataCollector.TagFieldMapping {
        .init(
            genreField: genreField.coreFieldType,
            timingField: timingField.coreFieldType,
            moodField: moodField.coreFieldType,
            descriptiveField: descriptiveField.coreFieldType
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
            minSamplesPerTag: minSamplesPerTag
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
}

// MARK: - TrainView

struct TrainView: View {
    // Use shared view model that persists across tab switches
    @StateObject private var viewModel = TrainingViewModel.shared

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
    }

    // MARK: - Folder Selection View

    private var folderSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Select Training Data")
                .font(.title)
                .fontWeight(.semibold)

            Text("Choose folders containing your tagged MP3 files")
                .foregroundStyle(.secondary)

            if !viewModel.selectedFolders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.selectedFolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            Text(folder.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                viewModel.selectedFolders.removeAll { $0 == folder }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(maxWidth: 400)
                .padding(.vertical)
            }

            HStack(spacing: 16) {
                Button {
                    selectFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    showTagSelectionSheet = true
                } label: {
                    Label("Configure & Scan", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
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

        return VStack(spacing: 16) {
            // Header with status and controls
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if viewModel.isPaused {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(.orange)
                        } else {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isPaused ? "Paused" : phase)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    if let tag = currentTag {
                        Text("Training: \(tag)")
                            .foregroundStyle(.secondary)
                    } else if let currentFile = detailedProgress.currentFile {
                        Text(currentFile)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if showFeatureInfo {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption)
                            Text("Discogs-EffNet (1280-dim)")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                    }
                }

                Spacer()

                // Control buttons
                HStack(spacing: 12) {
                    if viewModel.isPaused {
                        Button {
                            viewModel.isPaused = false
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Resume")
                    } else {
                        Button {
                            viewModel.isPaused = true
                        } label: {
                            Image(systemName: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Pause")
                    }

                    Button {
                        viewModel.cancelTraining()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .help("Cancel")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .fontWeight(.medium)
                }
                .font(.subheadline)

                ProgressView(value: progress)
                    .tint(viewModel.isPaused ? .orange : .blue)
            }

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatBox(
                    title: "Files",
                    value: "\(detailedProgress.processed)",
                    subtitle: "/ \(detailedProgress.total)"
                )
                StatBox(
                    title: "Tags",
                    value: "\(viewModel.selectedTags.totalCount)",
                    subtitle: "selected"
                )
                StatBox(
                    title: "Time/File",
                    value: calculateAverageTime(processed: detailedProgress.processed),
                    subtitle: ""
                )
                StatBox(
                    title: "ETA",
                    value: calculateETA(processed: detailedProgress.processed, total: detailedProgress.total),
                    subtitle: ""
                )
            }

            // Track list
            trackListView(detailedProgress: detailedProgress)
        }
        .padding()
        .onAppear {
            // Set training start time when progress view appears
            if viewModel.trainingStartTime == nil {
                viewModel.trainingStartTime = Date()
            }
        }
    }

    // MARK: - Track List View

    private func trackListView(detailedProgress: TrainingCoordinator.DetailedProgress) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text("\(detailedProgress.total) files")
                        .font(.headline)

                    if detailedProgress.processed < detailedProgress.total {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("\(detailedProgress.total - detailedProgress.processed) active")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                    } else if detailedProgress.total > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Complete")
                                .foregroundStyle(.green)
                        }
                        .font(.caption)
                    }

                    Spacer()
                }

                Divider()

                if detailedProgress.allFiles.isEmpty {
                    Text("Waiting for files...")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // Full file list with status
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(detailedProgress.allFiles.enumerated()), id: \.offset) { index, fileName in
                                    FileStatusRow(
                                        fileName: fileName,
                                        status: fileStatus(for: index, progress: detailedProgress),
                                        isCurrentFile: detailedProgress.currentFile == fileName
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 300)
                        .onChange(of: detailedProgress.processed) { _, newValue in
                            // Auto-scroll to keep current file visible
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(max(0, newValue - 2), anchor: .top)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    /// Determine status for a file based on its index and progress
    private func fileStatus(for index: Int, progress: TrainingCoordinator.DetailedProgress) -> FileProcessingStatus {
        if index < progress.processed {
            return .completed
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
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Packaging Model...")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Creating model bundle and metadata")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Complete View

    private func completeView(modelName: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Training Complete!")
                .font(.title)
                .fontWeight(.semibold)

            Text("Model: \(modelName)")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let summary = viewModel.trainingSummary {
                VStack(spacing: 12) {
                    summaryRow(label: "Trained Tags", value: "\(summary.trainedTags.count)")
                    summaryRow(label: "Skipped Tags", value: "\(summary.skippedTags.count)")
                    summaryRow(label: "Total Tracks", value: "\(summary.totalTracks)")
                    summaryRow(label: "Average Accuracy", value: String(format: "%.1f%%", summary.averageAccuracy * 100))
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 300)
            }

            Button {
                viewModel.resetState()
            } label: {
                Label("Train Another Model", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)

            Spacer()
        }
        .padding()
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Failed View

    private func failedView(error: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Training Failed")
                .font(.title)
                .fontWeight(.semibold)

            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button {
                viewModel.resetState()
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent)
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
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)

                    Text("Configure ID3 Field Mapping")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Tell CrateBot which ID3 fields contain your Genre, Timing, Mood, and Descriptive tags.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 450)
                }
                .padding(.top, 30)

                // Field Mapping Configuration
                GroupBox {
                    VStack(spacing: 16) {
                        fieldMappingRow("Genre", selection: $tagMapping.genreField, color: .purple)
                        Divider()
                        fieldMappingRow("Timing", selection: $tagMapping.timingField, color: .blue)
                        Divider()
                        fieldMappingRow("Mood", selection: $tagMapping.moodField, color: .orange)
                        Divider()
                        fieldMappingRow("Descriptive", selection: $tagMapping.descriptiveField, color: .green)
                    }
                    .padding()
                }
                .frame(maxWidth: 550)

                Button {
                    scanDirectory()
                } label: {
                    Label("Scan for Tags", systemImage: "magnifyingglass")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top)
                .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private func fieldMappingRow(_ label: String, selection: Binding<ID3Field>, color: Color) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(label)
                    .fontWeight(.medium)
            }
            .frame(width: 120, alignment: .leading)

            Picker("", selection: selection) {
                ForEach(ID3Field.allCases) { field in
                    Text(field.shortName).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Text(selection.wrappedValue.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: scanProgress)
                .progressViewStyle(.linear)
                .frame(width: 300)

            Text("Scanning for tags...")
                .font(.title3)
                .fontWeight(.medium)

            Text("\(filesScanned) / \(totalFiles) files")
                .foregroundStyle(.secondary)

            if let file = currentFile {
                Text(file)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .buttonStyle(.bordered)

                Spacer()

                Text("Found \(discovered.totalFiles) files")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))

            // Model name
            HStack {
                Text("Model Name:")
                    .fontWeight(.medium)
                TextField("Enter model name", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }
            .padding()

            Divider()

            // Tag categories
            ScrollView {
                VStack(spacing: 20) {
                    tagSection("Genre", color: .purple, tags: discovered.genre, selection: $selectedTags.genre)
                    tagSection("Timing", color: .blue, tags: discovered.timing, selection: $selectedTags.timing)
                    tagSection("Mood", color: .orange, tags: discovered.mood, selection: $selectedTags.mood)
                    tagSection("Descriptive", color: .green, tags: discovered.descriptive, selection: $selectedTags.descriptive)
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Text("\(selectedTags.totalCount) tags selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
        }
    }

    private func tagSection(_ title: String, color: Color, tags: [String: Int], selection: Binding<Set<String>>) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                    Text(title)
                        .font(.headline)
                    Text("(\(selection.wrappedValue.count)/\(tags.count) selected)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()

                    if !tags.isEmpty {
                        Button(selection.wrappedValue.count == tags.count ? "Deselect All" : "Select All") {
                            if selection.wrappedValue.count == tags.count {
                                selection.wrappedValue = []
                            } else {
                                selection.wrappedValue = Set(tags.keys)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }

                if tags.isEmpty {
                    Text("No tags found in this field")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 8) {
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
            .padding()
        }
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
                    .foregroundStyle(isSelected ? color : .secondary)

                Text(tag)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)

                Spacer()

                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(tag)
    }
}

// MARK: - Stat Box Component

struct StatBox: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - File Processing Status

enum FileProcessingStatus {
    case pending
    case processing
    case completed
    case failed
}

// MARK: - File Status Row

struct FileStatusRow: View {
    let fileName: String
    let status: FileProcessingStatus
    let isCurrentFile: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIcon
                .frame(width: 20, height: 20)

            // File name
            Text(fileName)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Status text
            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isCurrentFile ? Color.orange.opacity(0.1) : Color.clear)
        .background(status == .completed ? Color.green.opacity(0.05) : Color.clear)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
        case .processing:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusText: String {
        switch status {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Complete"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    TrainView()
}
