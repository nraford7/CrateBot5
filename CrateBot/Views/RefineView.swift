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
        .background(Theme.Colors.bgWindow)
    }

    // MARK: - File List Pane

    private var fileListPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Files to Review")
                    .font(Theme.Fonts.heading(16))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("\(appState.refineQueue.count)")
                    .font(Theme.Fonts.mono(12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.bgSurface)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            if appState.refineQueue.isEmpty {
                emptyFileListView
            } else {
                fileList
            }
        }
        .background(Theme.Colors.bgSurface)
    }

    private var emptyFileListView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("No files to review")
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textSecondary)
            Text("Tagged files will appear here for refinement")
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textTertiary)
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
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bgSurface)
    }

    private func fileRow(_ file: AppState.RefineFile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(file.fileName)
                    .font(Theme.Fonts.mono(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if file.hasChanges {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(Theme.Colors.accentPrimary)
                        .font(.caption)
                }
            }

            Text(file.tagsSummary)
                .font(Theme.Fonts.body(11))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func removeFiles(at offsets: IndexSet) {
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
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Select a file to review")
                .font(Theme.Fonts.heading(18))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.bgWindow)
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
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.bgElevated)

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            // Tag editor section
            ScrollView {
                tagEditorSection
                    .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.bgWindow)

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            // Bottom controls
            bottomControls
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.bgElevated)
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
        VStack(spacing: Theme.Spacing.md) {
            // File name
            Text(file.fileName)
                .font(Theme.Fonts.heading(16))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            // Waveform placeholder
            waveformPlaceholder

            // Progress bar
            progressBar

            // Time display
            HStack {
                Text(formatTime(appState.audioPlayer.currentTime))
                    .font(Theme.Fonts.mono(12))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text(formatTime(appState.audioPlayer.duration))
                    .font(Theme.Fonts.mono(12))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            // Playback controls
            playbackControls

            // Error message
            if let error = playbackError {
                Text(error)
                    .font(Theme.Fonts.body(12))
                    .foregroundColor(Theme.Colors.statusError)
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
                        .fill(isPlayed ? Theme.Colors.accentPrimary : Theme.Colors.textTertiary.opacity(0.3))
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
                    .fill(Theme.Colors.bgSurface)
                    .frame(height: 4)
                    .clipShape(Capsule())

                // Progress fill
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.Colors.accentPrimary, Theme.Colors.statusWarning],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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
        HStack(spacing: Theme.Spacing.lg) {
            // Skip backward 10s
            Button {
                let newTime = max(0, appState.audioPlayer.currentTime - 10)
                appState.audioPlayer.seek(to: newTime)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.title2)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(appState.audioPlayer.duration == 0)

            // Play/Pause
            Button {
                togglePlayback()
            } label: {
                Image(systemName: appState.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Colors.accentPrimary)
            }
            .buttonStyle(.plain)

            // Skip forward 10s
            Button {
                let newTime = min(appState.audioPlayer.duration, appState.audioPlayer.currentTime + 10)
                appState.audioPlayer.seek(to: newTime)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.title2)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(appState.audioPlayer.duration == 0)
        }
    }

    private func togglePlayback() {
        if appState.audioPlayer.isPlaying {
            appState.audioPlayer.pause()
        } else if appState.audioPlayer.duration > 0 {
            appState.audioPlayer.resume()
        } else {
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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Genre
            tagField(title: "Genre", value: $editedGenre, confidence: file.confidences?["genre"], category: .genre)

            // Timing
            tagField(title: "Timing", value: $editedTiming, confidence: file.confidences?["timing"], category: .timing)

            // Mood (multi-value)
            multiTagField(
                title: "Mood",
                tags: $editedMood,
                newTag: $newMoodTag,
                confidenceKey: "mood",
                category: .mood
            )

            // Descriptive (multi-value)
            multiTagField(
                title: "Descriptive",
                tags: $editedDescriptive,
                newTag: $newDescriptiveTag,
                confidenceKey: "descriptive",
                category: .descriptive
            )
        }
    }

    private func tagField(title: String, value: Binding<String>, confidence: Float?, category: CategoryTagChip.Category) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(Theme.Fonts.label(14))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                if let conf = confidence {
                    confidenceBadge(conf)
                }
            }

            TextField("Enter \(title.lowercased())", text: value)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Fonts.body(13))
        }
    }

    private func multiTagField(
        title: String,
        tags: Binding<[String]>,
        newTag: Binding<String>,
        confidenceKey: String,
        category: CategoryTagChip.Category
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(Theme.Fonts.label(14))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                if let conf = file.confidences?[confidenceKey] {
                    confidenceBadge(conf)
                }
            }

            // Current tags
            if !tags.wrappedValue.isEmpty {
                FlowLayout(spacing: Theme.Spacing.sm) {
                    ForEach(tags.wrappedValue, id: \.self) { tag in
                        CategoryTagChip(tag: tag, category: category) {
                            tags.wrappedValue.removeAll { $0 == tag }
                        }
                    }
                }
            }

            // Add new tag
            HStack {
                TextField("Add \(title.lowercased()) tag", text: newTag)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Fonts.body(13))
                    .onSubmit {
                        addTag(to: tags, from: newTag)
                    }

                Button {
                    addTag(to: tags, from: newTag)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.Colors.accentPrimary)
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

    private func confidenceBadge(_ confidence: Float) -> some View {
        let percentage = Int(confidence * 100)
        let color: Color = confidence >= 0.8 ? Theme.Colors.statusSuccess :
                          confidence >= 0.5 ? Theme.Colors.statusWarning : Theme.Colors.statusError

        return Text("\(percentage)%")
            .font(Theme.Fonts.label(10))
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            Button("Reset") {
                loadEditedValues()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!hasChanges)

            Spacer()

            Button {
                saveChanges()
            } label: {
                Label("Save Changes", systemImage: "checkmark.circle")
            }
            .buttonStyle(PrimaryButtonStyle())
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
