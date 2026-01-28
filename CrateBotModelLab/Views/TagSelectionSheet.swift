import SwiftUI
import CrateBotCore

struct TagSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ModelLabState.self) private var labState

    @State private var selectedGenre: Set<String> = []
    @State private var selectedTiming: Set<String> = []
    @State private var selectedMood: Set<String> = []
    @State private var selectedDescriptive: Set<String> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var filesScanned: Int = 0
    @State private var totalFiles: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isScanning {
                    scanningView
                } else if let discovered = labState.discoveredTags {
                    tagSelectionView(discovered)
                } else {
                    scanPromptView
                }
            }
            .navigationTitle("Select Training Tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                if labState.discoveredTags != nil && !isScanning {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start Training") {
                            startTraining()
                        }
                        .disabled(selectedGenre.isEmpty && selectedTiming.isEmpty && selectedMood.isEmpty && selectedDescriptive.isEmpty)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private var scanPromptView: some View {
        @Bindable var state = labState

        return ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)

                    Text("Configure & Scan")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Configure which ID3 fields to use for each training category, then scan your directory.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .padding(.top, 20)

                // ID3 Field Mapping Configuration
                GroupBox("ID3 Field Mapping") {
                    VStack(spacing: 16) {
                        fieldMappingRow("Genre", selection: $state.tagMapping.genreField)
                        fieldMappingRow("Timing", selection: $state.tagMapping.timingField)
                        fieldMappingRow("Mood", selection: $state.tagMapping.moodField)
                        fieldMappingRow("Descriptive", selection: $state.tagMapping.descriptiveField)
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: 500)

                Button("Scan Now") {
                    scanDirectory()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private func fieldMappingRow(_ label: String, selection: Binding<ID3Field>) -> some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)

            Picker("", selection: selection) {
                ForEach(ID3Field.allCases) { field in
                    Text(field.shortName).tag(field)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Text(selection.wrappedValue.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .leading)
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView(value: scanProgress)
                .progressViewStyle(.linear)
                .frame(width: 200)

            Text("Scanning directory...")
                .font(.title3)

            Text("\(filesScanned) / \(totalFiles) files")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let current = labState.currentFile {
                Text(current)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tagSelectionView(_ discovered: ModelLabState.DiscoveredTags) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Found \(discovered.totalFiles) files. Select tags to train:")

                    Spacer()

                    Button {
                        // Clear discovered tags to go back to mapping configuration
                        labState.discoveredTags = nil
                        selectedGenre = []
                        selectedTiming = []
                        selectedMood = []
                        selectedDescriptive = []
                    } label: {
                        Label("Change Mapping", systemImage: "arrow.left")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                tagSection("Genre", tags: discovered.genre, selection: $selectedGenre)
                tagSection("Timing", tags: discovered.timing, selection: $selectedTiming)
                tagSection("Mood", tags: discovered.mood, selection: $selectedMood)
                tagSection("Descriptive", tags: discovered.descriptive, selection: $selectedDescriptive)
            }
            .padding(.vertical)
        }
    }

    private func tagSection(_ title: String, tags: [String: Int], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)

                Text("(\(selection.wrappedValue.count)/\(tags.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(selection.wrappedValue.count == tags.count ? "Deselect All" : "Select All") {
                    if selection.wrappedValue.count == tags.count {
                        selection.wrappedValue = []
                    } else {
                        selection.wrappedValue = Set(tags.keys)
                    }
                }
                .font(.caption)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 8) {
                    ForEach(tags.sorted(by: { $0.value > $1.value }), id: \.key) { tag, count in
                        TagToggle(tag: tag, count: count, isSelected: selection.wrappedValue.contains(tag)) {
                            if selection.wrappedValue.contains(tag) {
                                selection.wrappedValue.remove(tag)
                            } else {
                                selection.wrappedValue.insert(tag)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }

    private func scanDirectory() {
        guard let directory = labState.trainingDirectory else { return }

        isScanning = true
        scanProgress = 0
        filesScanned = 0
        totalFiles = 0

        // Capture the mapping configuration
        let mapping = labState.tagMapping.coreMapping

        Task {
            let collector = TrainingDataCollector()
            let result = await collector.discoverCategorizedTags(
                from: [directory],
                mapping: mapping
            ) { progress in
                await MainActor.run {
                    self.filesScanned = progress.processed
                    self.totalFiles = progress.total
                    self.scanProgress = progress.fraction
                    if let file = progress.currentFile {
                        labState.currentFile = file.lastPathComponent
                    }
                }
            }

            await MainActor.run {
                labState.discoveredTags = .init(
                    genre: result.genre,
                    timing: result.timing,
                    mood: result.mood,
                    descriptive: result.descriptive,
                    totalFiles: result.totalFiles
                )
                labState.currentFile = nil
                isScanning = false
            }
        }
    }

    private func startTraining() {
        labState.selectedTags = .init(
            genre: Array(selectedGenre),
            timing: Array(selectedTiming),
            mood: Array(selectedMood),
            descriptive: Array(selectedDescriptive)
        )
        labState.trainingStatus = .running
        labState.startTime = Date()
        dismiss()
    }
}

struct TagToggle: View {
    let tag: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(tag)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Spacer()

                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(tag)  // Shows full text on hover
    }
}

#Preview {
    TagSelectionSheet()
        .environment(ModelLabState())
}
