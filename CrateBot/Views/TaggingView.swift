import SwiftUI
import CrateBotCore
import UniformTypeIdentifiers
import AppKit

struct TaggingView: View {
    @Environment(AppState.self) private var appState
    @State private var isDropTargeted = false
    @State private var taggingTask: Task<Void, Never>?
    @State private var lastTaggingResult: TaggingResult?
    @State private var showResultsSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Drop zone or file queue
            if appState.queuedFiles.isEmpty {
                dropZoneView
            } else {
                fileQueueView
            }

            // Bottom controls
            controlsBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )

            VStack(spacing: 16) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)

                Text("Drop MP3 Files Here")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Or drag folders to add all MP3s")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    openFilePicker()
                } label: {
                    Label("Browse Files", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding(24)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - File Queue

    private var fileQueueView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(appState.queuedFiles.count) file\(appState.queuedFiles.count == 1 ? "" : "s") queued")
                    .font(.headline)

                Spacer()

                Button {
                    openFilePicker()
                } label: {
                    Label("Add More", systemImage: "plus")
                }
                .disabled(appState.isTagging)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            // File list
            List {
                ForEach(appState.queuedFiles) { file in
                    fileRow(file)
                }
                .onDelete { indexSet in
                    if !appState.isTagging {
                        removeFiles(at: indexSet)
                    }
                }
            }
            .listStyle(.inset)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.1))
                        .padding(4)
                }
            }
        }
    }

    private func fileRow(_ file: AppState.QueuedFile) -> some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon(for: file.status)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let error = file.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if file.status == .complete, let summary = file.tagsSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Show tag details button for completed files
            if file.status == .complete, let tags = file.writtenTags {
                Button {
                    showTagDetails(tags, for: file.fileName)
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("View tag details")
            }

            // Remove button (only when not tagging and not processing this file)
            if !appState.isTagging && file.status != .processing {
                Button {
                    removeFile(file)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func showTagDetails(_ tags: AppState.WrittenTags, for fileName: String) {
        // Build detail message
        var details: [String] = []

        // User predictions section
        var userSection: [String] = []
        if let genre = tags.userGenre { userSection.append("  Genre: \(genre)") }
        if let timing = tags.userTiming { userSection.append("  Timing: \(timing)") }
        if let mood = tags.userMood { userSection.append("  Mood: \(mood)") }
        if !tags.userDescriptive.isEmpty { userSection.append("  Tags: \(tags.userDescriptive.joined(separator: ", "))") }

        if !userSection.isEmpty {
            details.append("User Model Predictions:")
            details.append(contentsOf: userSection)
        }

        // Essentia predictions section
        var essentiaSection: [String] = []
        if !tags.essentiaGenres.isEmpty { essentiaSection.append("  Genres: \(tags.essentiaGenres.joined(separator: ", "))") }
        if !tags.essentiaMoods.isEmpty { essentiaSection.append("  Moods: \(tags.essentiaMoods.joined(separator: ", "))") }
        if !tags.essentiaInstruments.isEmpty { essentiaSection.append("  Instruments: \(tags.essentiaInstruments.joined(separator: ", "))") }

        if !essentiaSection.isEmpty {
            if !details.isEmpty { details.append("") }
            details.append("Essentia Predictions:")
            details.append(contentsOf: essentiaSection)
        }

        let message = details.isEmpty ? "No tags were written" : details.joined(separator: "\n")

        // Show alert with details
        let alert = NSAlert()
        alert.messageText = "Tags for \(fileName)"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @ViewBuilder
    private func statusIcon(for status: AppState.QueuedFile.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .processing:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        VStack(spacing: 12) {
            // Progress bar (only during tagging)
            if appState.isTagging {
                VStack(spacing: 4) {
                    ProgressView(value: appState.taggingProgress)

                    HStack {
                        Text("Processing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(appState.taggingProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Action buttons
            HStack {
                if !appState.queuedFiles.isEmpty {
                    Button("Clear All") {
                        clearQueue()
                    }
                    .disabled(appState.isTagging)
                }

                Spacer()

                if appState.isTagging {
                    Button("Cancel") {
                        cancelTagging()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        startTagging()
                    } label: {
                        Label("Start Tagging", systemImage: "tag.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.queuedFiles.isEmpty)
                    // TODO: Re-enable model check once ModelManager is integrated
                    // .disabled(appState.queuedFiles.isEmpty || !appState.modelLoaded)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        // Note: Not setting allowedContentTypes to allow folder selection
        // MP3 filtering happens in addFiles(from:)

        if panel.runModal() == .OK {
            addFiles(from: panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                DispatchQueue.main.async {
                    addFiles(from: [url])
                }
            }
        }
    }

    private func addFiles(from urls: [URL]) {
        var filesToAdd: [URL] = []

        for url in urls {
            if url.hasDirectoryPath {
                // Recursively find MP3s in directory
                let mp3s = findMP3Files(in: url)
                filesToAdd.append(contentsOf: mp3s)
            } else if url.pathExtension.lowercased() == "mp3" {
                filesToAdd.append(url)
            }
        }

        // Filter out duplicates
        let existingURLs = Set(appState.queuedFiles.map(\.url))
        let newFiles = filesToAdd
            .filter { !existingURLs.contains($0) }
            .map { AppState.QueuedFile(url: $0) }

        appState.queuedFiles.append(contentsOf: newFiles)
    }

    private func findMP3Files(in directory: URL) -> [URL] {
        var mp3Files: [URL] = []

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return mp3Files
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "mp3" {
                mp3Files.append(fileURL)
            }
        }

        return mp3Files
    }

    private func removeFile(_ file: AppState.QueuedFile) {
        appState.queuedFiles.removeAll { $0.id == file.id }
    }

    private func removeFiles(at offsets: IndexSet) {
        appState.queuedFiles.remove(atOffsets: offsets)
    }

    private func clearQueue() {
        appState.queuedFiles.removeAll()
        appState.taggingProgress = 0.0
    }

    private func startTagging() {
        appState.isTagging = true
        appState.taggingProgress = 0.0

        // Reset all files to pending
        for index in appState.queuedFiles.indices {
            appState.queuedFiles[index].status = .pending
            appState.queuedFiles[index].error = nil
        }

        // Start the tagging task
        taggingTask = Task {
            await performTagging()
        }
    }

    private func cancelTagging() {
        // Cancel the task
        taggingTask?.cancel()
        taggingTask = nil

        appState.isTagging = false
        appState.taggingProgress = 0.0

        // Reset any processing files back to pending
        for index in appState.queuedFiles.indices {
            if appState.queuedFiles[index].status == .processing {
                appState.queuedFiles[index].status = .pending
            }
        }
    }

    // MARK: - Tagging Engine Integration

    private func performTagging() async {
        let totalFiles = appState.queuedFiles.count
        guard totalFiles > 0 else {
            await MainActor.run {
                appState.isTagging = false
            }
            return
        }

        // Initialize engine and manager
        let engine: TaggingEngine
        do {
            engine = try TaggingEngine()
        } catch {
            await MainActor.run {
                appState.isTagging = false
                appState.showToast("Failed to initialize tagging engine: \(error.localizedDescription)", kind: .error)
            }
            return
        }

        let id3Manager = ID3Manager()
        let overwrite = appState.taggingPreferences.overwrite

        for (index, file) in appState.queuedFiles.enumerated() {
            // Check for cancellation
            if Task.isCancelled { break }

            // Update status to processing
            await MainActor.run {
                if index < appState.queuedFiles.count {
                    appState.queuedFiles[index].status = .processing
                }
            }

            do {
                // Analyze the file with TaggingEngine
                let result = try await engine.analyze(url: file.url)

                // Build tags to write
                var tagsToWrite = TagsToWrite(overwrite: overwrite)

                // Build written tags record for display
                var writtenTags = AppState.WrittenTags()

                // User predictions -> Primary fields (if available)
                if let user = result.userPredictions {
                    tagsToWrite.genre = user.genre
                    tagsToWrite.timing = user.timing
                    tagsToWrite.mood = user.mood
                    if !user.descriptive.isEmpty {
                        tagsToWrite.comments = user.descriptive.joined(separator: ", ")
                    }

                    // Store for display
                    writtenTags.userGenre = user.genre
                    writtenTags.userTiming = user.timing
                    writtenTags.userMood = user.mood
                    writtenTags.userDescriptive = user.descriptive
                }

                // Essentia predictions -> Secondary fields (always available)
                let essentia = result.essentiaTags
                if !essentia.genres.isEmpty {
                    tagsToWrite.essentiaGenres = essentia.genresString
                    writtenTags.essentiaGenres = essentia.genres
                }
                if !essentia.moods.isEmpty {
                    tagsToWrite.essentiaMoods = essentia.moodsString
                    writtenTags.essentiaMoods = essentia.moods
                }
                if !essentia.instruments.isEmpty {
                    tagsToWrite.essentiaInstruments = essentia.instrumentsString
                    writtenTags.essentiaInstruments = essentia.instruments
                }

                // Write tags to file
                try await id3Manager.writeTags(tagsToWrite, to: file.url)

                // Update status to complete and store written tags
                await MainActor.run {
                    if index < appState.queuedFiles.count {
                        appState.queuedFiles[index].status = .complete
                        appState.queuedFiles[index].writtenTags = writtenTags
                    }
                    lastTaggingResult = result
                }

            } catch {
                // Update status to error
                await MainActor.run {
                    if index < appState.queuedFiles.count {
                        appState.queuedFiles[index].status = .error
                        appState.queuedFiles[index].error = error.localizedDescription
                    }
                }
            }

            // Update progress
            await MainActor.run {
                appState.taggingProgress = Double(index + 1) / Double(totalFiles)
            }
        }

        // Tagging complete
        await MainActor.run {
            appState.isTagging = false
            let completedCount = appState.queuedFiles.filter { $0.status == .complete }.count
            let errorCount = appState.queuedFiles.filter { $0.status == .error }.count

            if errorCount == 0 {
                appState.showToast("Tagged \(completedCount) file\(completedCount == 1 ? "" : "s") successfully")
            } else {
                appState.showToast("Tagged \(completedCount) file\(completedCount == 1 ? "" : "s"), \(errorCount) failed", kind: .error)
            }
        }
    }
}

#Preview {
    @Previewable @State var previewState = AppState()

    TaggingView()
        .environment(previewState)
        .frame(width: 600, height: 500)
        .onAppear {
            // Add sample files for preview
            previewState.queuedFiles = [
                AppState.QueuedFile(url: URL(fileURLWithPath: "/Music/track1.mp3")),
                AppState.QueuedFile(url: URL(fileURLWithPath: "/Music/track2.mp3")),
                AppState.QueuedFile(url: URL(fileURLWithPath: "/Music/track3.mp3"))
            ]
            previewState.modelLoaded = true
        }
}

#Preview("Empty State") {
    TaggingView()
        .environment(AppState())
        .frame(width: 600, height: 500)
}

#Preview("Processing") {
    @Previewable @State var processingState = AppState()

    TaggingView()
        .environment(processingState)
        .frame(width: 600, height: 500)
        .onAppear {
            processingState.queuedFiles = [
                AppState.QueuedFile(url: URL(fileURLWithPath: "/Music/complete.mp3"), status: .complete),
                AppState.QueuedFile(url: URL(fileURLWithPath: "/Music/processing.mp3"), status: .processing),
                AppState.QueuedFile(url: URL(fileURLWithPath: "/Music/pending.mp3"), status: .pending),
                AppState.QueuedFile(url: URL(fileURLWithPath: "/Music/error.mp3"), status: .error, error: "Could not read file")
            ]
            processingState.isTagging = true
            processingState.taggingProgress = 0.35
            processingState.modelLoaded = true
        }
}
