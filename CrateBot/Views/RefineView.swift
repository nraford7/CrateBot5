import SwiftUI
import CrateBotCore

struct RefineView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HSplitView {
            // Left: File list
            fileListPane
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)

            // Right: Detail pane
            detailPane
                .frame(minWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File List Pane

    private var fileListPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Files to Review")
                    .font(.headline)
                Spacer()
                Text("\(appState.refineQueue.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if appState.refineQueue.isEmpty {
                emptyFileListView
            } else {
                fileList
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyFileListView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No files to review")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tagged files will appear here for refinement")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var fileList: some View {
        List(selection: Binding(
            get: { appState.selectedRefineFile?.id },
            set: { newID in
                if let id = newID {
                    appState.selectedRefineFile = appState.refineQueue.first { $0.id == id }
                } else {
                    appState.selectedRefineFile = nil
                }
            }
        )) {
            ForEach(appState.refineQueue) { file in
                fileRow(file)
                    .tag(file.id)
            }
            .onDelete(perform: removeFiles)
        }
        .listStyle(.sidebar)
    }

    private func fileRow(_ file: AppState.RefineFile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(file.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if file.hasChanges {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }
            }

            Text(file.tagsSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private func removeFiles(at offsets: IndexSet) {
        // Stop playback if removing the selected file
        let idsToRemove = offsets.map { appState.refineQueue[$0].id }
        if let selected = appState.selectedRefineFile, idsToRemove.contains(selected.id) {
            appState.audioPlayer.stop()
            appState.selectedRefineFile = nil
        }
        appState.refineQueue.remove(atOffsets: offsets)
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        Group {
            if let file = appState.selectedRefineFile {
                RefineDetailView(file: file)
            } else {
                noSelectionView
            }
        }
    }

    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a file to review")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - RefineDetailView

private struct RefineDetailView: View {
    @Environment(AppState.self) private var appState
    let file: AppState.RefineFile

    @State private var editedGenre: String = ""
    @State private var editedMood: [String] = []
    @State private var editedTiming: String = ""
    @State private var editedDescriptive: [String] = []
    @State private var newMoodTag: String = ""
    @State private var newDescriptiveTag: String = ""
    @State private var playbackError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Audio player section
            audioPlayerSection
                .padding(20)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Tag editor section
            ScrollView {
                tagEditorSection
                    .padding(20)
            }

            Divider()

            // Bottom controls
            bottomControls
                .padding(16)
                .background(.regularMaterial)
        }
        .onAppear {
            loadEditedValues()
        }
        .onChange(of: file.id) { _, _ in
            loadEditedValues()
            appState.audioPlayer.stop()
            playbackError = nil
        }
        .onDisappear {
            appState.audioPlayer.stop()
        }
    }

    private func loadEditedValues() {
        editedGenre = file.genre ?? ""
        editedMood = file.mood
        editedTiming = file.timing ?? ""
        editedDescriptive = file.descriptive
    }

    // MARK: - Audio Player Section

    private var audioPlayerSection: some View {
        VStack(spacing: 16) {
            // File name
            Text(file.fileName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            // Waveform placeholder
            waveformPlaceholder

            // Progress bar
            progressBar

            // Time display
            HStack {
                Text(formatTime(appState.audioPlayer.currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(appState.audioPlayer.duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Playback controls
            playbackControls

            // Error message
            if let error = playbackError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private let waveformBarCount = 40
    private let waveformBarSpacing: CGFloat = 2

    private var waveformPlaceholder: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(waveformBarCount - 1) * waveformBarSpacing
            let barWidth = max(2, (geometry.size.width - totalSpacing) / CGFloat(waveformBarCount))

            HStack(spacing: waveformBarSpacing) {
                ForEach(0..<waveformBarCount, id: \.self) { index in
                    let height = waveformBarHeight(index: index, totalBars: waveformBarCount)
                    let isPlayed = Double(index) / Double(waveformBarCount) < appState.audioPlayer.progress

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isPlayed ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(
                            width: barWidth,
                            height: height * geometry.size.height
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 60)
    }

    private func waveformBarHeight(index: Int, totalBars: Int) -> CGFloat {
        // Generate pseudo-random but deterministic heights based on file name
        let seed = file.fileName.hashValue
        let noise = sin(Double(index * 7 + seed)) * 0.3 +
                   cos(Double(index * 13 + seed)) * 0.2 +
                   sin(Double(index * 23 + seed)) * 0.15
        return CGFloat(0.3 + abs(noise) * 0.7)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)
                    .clipShape(Capsule())

                // Progress fill
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * appState.audioPlayer.progress, height: 4)
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        appState.audioPlayer.seek(toProgress: progress)
                    }
            )
        }
        .frame(height: 4)
    }

    private var playbackControls: some View {
        HStack(spacing: 24) {
            // Skip backward 10s
            Button {
                let newTime = max(0, appState.audioPlayer.currentTime - 10)
                appState.audioPlayer.seek(to: newTime)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(appState.audioPlayer.duration == 0)

            // Play/Pause
            Button {
                togglePlayback()
            } label: {
                Image(systemName: appState.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            // Skip forward 10s
            Button {
                let newTime = min(appState.audioPlayer.duration, appState.audioPlayer.currentTime + 10)
                appState.audioPlayer.seek(to: newTime)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(appState.audioPlayer.duration == 0)
        }
    }

    private func togglePlayback() {
        if appState.audioPlayer.isPlaying {
            appState.audioPlayer.pause()
        } else if appState.audioPlayer.duration > 0 {
            // Resume existing playback
            appState.audioPlayer.resume()
        } else {
            // Start new playback
            do {
                try appState.audioPlayer.play(url: file.url)
                playbackError = nil
            } catch {
                playbackError = "Failed to play: \(error.localizedDescription)"
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Tag Editor Section

    private var tagEditorSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Genre
            tagField(title: "Genre", value: $editedGenre, confidence: file.confidences?["genre"])

            // Timing
            tagField(title: "Timing", value: $editedTiming, confidence: file.confidences?["timing"])

            // Mood (multi-value)
            multiTagField(
                title: "Mood",
                tags: $editedMood,
                newTag: $newMoodTag,
                confidenceKey: "mood"
            )

            // Descriptive (multi-value)
            multiTagField(
                title: "Descriptive",
                tags: $editedDescriptive,
                newTag: $newDescriptiveTag,
                confidenceKey: "descriptive"
            )
        }
    }

    private func tagField(title: String, value: Binding<String>, confidence: Float?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let conf = confidence {
                    confidenceBadge(conf)
                }
            }

            TextField("Enter \(title.lowercased())", text: value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func multiTagField(
        title: String,
        tags: Binding<[String]>,
        newTag: Binding<String>,
        confidenceKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let conf = file.confidences?[confidenceKey] {
                    confidenceBadge(conf)
                }
            }

            // Current tags
            FlowLayout(spacing: 6) {
                ForEach(tags.wrappedValue, id: \.self) { tag in
                    tagChip(tag) {
                        tags.wrappedValue.removeAll { $0 == tag }
                    }
                }
            }

            // Add new tag
            HStack {
                TextField("Add \(title.lowercased()) tag", text: newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addTag(to: tags, from: newTag)
                    }

                Button {
                    addTag(to: tags, from: newTag)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newTag.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTag(to tags: Binding<[String]>, from newTag: Binding<String>) {
        let trimmed = newTag.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.wrappedValue.contains(trimmed) else { return }
        tags.wrappedValue.append(trimmed)
        newTag.wrappedValue = ""
    }

    private func tagChip(_ tag: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private func confidenceBadge(_ confidence: Float) -> some View {
        let percentage = Int(confidence * 100)
        let color: Color = confidence >= 0.8 ? .green :
                          confidence >= 0.5 ? .orange : .red

        return Text("\(percentage)%")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            // Discard changes button
            Button("Reset") {
                loadEditedValues()
            }
            .disabled(!hasChanges)

            Spacer()

            // Save changes button
            Button {
                saveChanges()
            } label: {
                Label("Save Changes", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges)
        }
    }

    private var hasChanges: Bool {
        editedGenre != (file.genre ?? "") ||
        editedTiming != (file.timing ?? "") ||
        editedMood != file.mood ||
        editedDescriptive != file.descriptive
    }

    private func saveChanges() {
        guard let index = appState.refineQueue.firstIndex(where: { $0.id == file.id }) else { return }

        appState.refineQueue[index].genre = editedGenre.isEmpty ? nil : editedGenre
        appState.refineQueue[index].timing = editedTiming.isEmpty ? nil : editedTiming
        appState.refineQueue[index].mood = editedMood
        appState.refineQueue[index].descriptive = editedDescriptive
        appState.refineQueue[index].hasChanges = true

        // Update selected file reference
        appState.selectedRefineFile = appState.refineQueue[index]

        appState.showToast("Changes saved")
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { continue }
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// MARK: - Previews

#Preview {
    @Previewable @State var previewState = AppState()

    RefineView()
        .environment(previewState)
        .frame(width: 900, height: 600)
        .onAppear {
            previewState.refineQueue = [
                AppState.RefineFile(
                    url: URL(fileURLWithPath: "/Music/track1.mp3"),
                    genre: "House",
                    mood: ["Energetic", "Uplifting"],
                    timing: "Fast",
                    descriptive: ["Synth", "Bass"],
                    confidences: ["genre": 0.92, "mood": 0.78, "timing": 0.85]
                ),
                AppState.RefineFile(
                    url: URL(fileURLWithPath: "/Music/track2_long_name_here.mp3"),
                    genre: "Techno",
                    mood: ["Dark"],
                    timing: "Medium"
                ),
                AppState.RefineFile(
                    url: URL(fileURLWithPath: "/Music/track3.mp3"),
                    confidences: ["genre": 0.45]
                )
            ]
            previewState.selectedRefineFile = previewState.refineQueue.first
        }
}

#Preview("Empty State") {
    RefineView()
        .environment(AppState())
        .frame(width: 900, height: 600)
}

#Preview("No Selection") {
    @Previewable @State var noSelectionState = AppState()

    RefineView()
        .environment(noSelectionState)
        .frame(width: 900, height: 600)
        .onAppear {
            noSelectionState.refineQueue = [
                AppState.RefineFile(
                    url: URL(fileURLWithPath: "/Music/track1.mp3"),
                    genre: "House",
                    mood: ["Energetic"]
                ),
                AppState.RefineFile(
                    url: URL(fileURLWithPath: "/Music/track2.mp3"),
                    genre: "Techno"
                )
            ]
        }
}
