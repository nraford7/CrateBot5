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
    @State private var showTaggingSettings = false

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
        .background(Theme.Colors.bgWindow)
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(
                    isDropTargeted ? Theme.Colors.accentPrimary : Theme.Colors.textTertiary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .fill(isDropTargeted ? Theme.Colors.accentPrimary.opacity(0.1) : Color.clear)
                )

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(isDropTargeted ? Theme.Colors.accentPrimary : Theme.Colors.textTertiary)

                Text("Drop MP3 Files Here")
                    .font(Theme.Fonts.heading(20))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Or drag folders to add all MP3s")
                    .font(Theme.Fonts.body(14))
                    .foregroundColor(Theme.Colors.textSecondary)

                Button {
                    openFilePicker()
                } label: {
                    Label("Browse Files", systemImage: "folder")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.lg)
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
                    .font(Theme.Fonts.heading(16))
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button {
                    openFilePicker()
                } label: {
                    Label("Add More", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(appState.isTagging)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            // File list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.queuedFiles) { file in
                        fileRow(file)
                        Divider().background(Theme.Colors.textTertiary.opacity(0.1))
                    }
                }
            }
            .background(Theme.Colors.bgSurface)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .strokeBorder(Theme.Colors.accentPrimary, lineWidth: 2)
                        .background(Theme.Colors.accentPrimary.opacity(0.1))
                        .padding(4)
                }
            }
        }
    }

    private func fileRow(_ file: AppState.QueuedFile) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Status icon
            statusIcon(for: file.status)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(Theme.Fonts.mono(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let error = file.error {
                    Text(error)
                        .font(Theme.Fonts.body(11))
                        .foregroundColor(Theme.Colors.statusError)
                } else if file.status == .complete, let summary = file.tagsSummary {
                    Text(summary)
                        .font(Theme.Fonts.body(11))
                        .foregroundColor(Theme.Colors.textSecondary)
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
                        .foregroundStyle(Theme.Colors.textTertiary)
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
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(file.status == .processing ? Theme.Colors.statusWarning.opacity(0.08) : Color.clear)
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
            StatusLED(status: .pending, size: 16)
        case .processing:
            ProgressView()
                .scaleEffect(0.6)
                .tint(Theme.Colors.statusWarning)
                .frame(width: 16, height: 16)
        case .complete:
            StatusLED(status: .complete, size: 16)
        case .error:
            StatusLED(status: .error, size: 16)
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Progress bar (only during tagging)
            if appState.isTagging {
                VStack(spacing: Theme.Spacing.xs) {
                    ThemedProgressBar(progress: appState.taggingProgress)

                    HStack {
                        Text("Processing...")
                            .font(Theme.Fonts.body(12))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text("\(Int(appState.taggingProgress * 100))%")
                            .font(Theme.Fonts.mono(12))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }

            // Action buttons
            HStack {
                if !appState.queuedFiles.isEmpty {
                    Button("Clear All") {
                        clearQueue()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(appState.isTagging)
                }

                Spacer()

                if appState.isTagging {
                    Button("Cancel") {
                        cancelTagging()
                    }
                    .buttonStyle(DangerButtonStyle())
                } else {
                    startTaggingButton
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.bgElevated)
    }

    @ViewBuilder
    private var startTaggingButton: some View {
        let isDisabled = appState.queuedFiles.isEmpty || !appState.modelLoaded

        Button {
            showTaggingSettings = true
        } label: {
            Label("Start Tagging", systemImage: "tag")
        }
        .buttonStyle(isDisabled ? AnyButtonStyle(DisabledButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
        .disabled(isDisabled)
        .sheet(isPresented: $showTaggingSettings) {
            TaggingSettingsSheet(onStartTagging: {
                startTagging()
            })
            .environment(appState)
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            addFilesWithBookmarks(from: panel.urls)
        }
    }

    /// Add files from NSOpenPanel with security-scoped access started immediately
    private func addFilesWithBookmarks(from urls: [URL]) {
        var filesToAdd: [(url: URL, startAccessImmediately: Bool)] = []

        for url in urls {
            if url.hasDirectoryPath {
                // For directories, start accessing and add folder bookmark
                _ = url.startAccessingSecurityScopedResource()
                do {
                    try appState.bookmarkManager.addFolderAccess(url)
                } catch {
                    print("Failed to bookmark folder: \(error)")
                }
                let mp3s = findMP3Files(in: url)
                filesToAdd.append(contentsOf: mp3s.map { ($0, false) })
            } else if url.pathExtension.lowercased() == "mp3" {
                filesToAdd.append((url, true))
            }
        }

        let existingURLs = Set(appState.queuedFiles.map(\.url))
        let newFiles = filesToAdd
            .filter { !existingURLs.contains($0.url) }
            .map { AppState.QueuedFile(url: $0.url, startAccessImmediately: $0.startAccessImmediately) }

        appState.queuedFiles.append(contentsOf: newFiles)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                DispatchQueue.main.async {
                    self.addDroppedFiles(from: [url])
                }
            }
        }
    }

    /// Add files from drag-and-drop (checks for folder access)
    private func addDroppedFiles(from urls: [URL]) {
        var filesToAdd: [URL] = []
        var filesWithoutAccess: [URL] = []

        for url in urls {
            if url.hasDirectoryPath {
                // Check if we have access to this directory
                if appState.bookmarkManager.hasAccess(to: url) {
                    let mp3s = findMP3Files(in: url)
                    filesToAdd.append(contentsOf: mp3s)
                } else {
                    // Try to add folder access (will work if Finder drag grants temporary access)
                    do {
                        try appState.bookmarkManager.addFolderAccess(url)
                        let mp3s = findMP3Files(in: url)
                        filesToAdd.append(contentsOf: mp3s)
                    } catch {
                        filesWithoutAccess.append(url)
                    }
                }
            } else if url.pathExtension.lowercased() == "mp3" {
                // Check if parent folder has access
                let parentFolder = url.deletingLastPathComponent()
                if appState.bookmarkManager.hasAccess(to: parentFolder) ||
                   FileManager.default.isWritableFile(atPath: url.path) {
                    filesToAdd.append(url)
                } else {
                    filesWithoutAccess.append(url)
                }
            }
        }

        // Add files we have access to
        let existingURLs = Set(appState.queuedFiles.map(\.url))
        let newFiles = filesToAdd
            .filter { !existingURLs.contains($0) }
            .map { AppState.QueuedFile(url: $0) }

        appState.queuedFiles.append(contentsOf: newFiles)

        // Warn about files we can't access
        if !filesWithoutAccess.isEmpty {
            showAccessDeniedAlert(fileCount: filesWithoutAccess.count)
        }
    }

    /// Show alert when dropped files can't be accessed
    private func showAccessDeniedAlert(fileCount: Int) {
        let alert = NSAlert()
        alert.messageText = "File Access Required"
        alert.informativeText = """
            \(fileCount) file\(fileCount == 1 ? "" : "s") could not be added due to macOS security restrictions.

            To write tags, please use the "Browse Files" button instead of drag-and-drop, or grant CrateBot Full Disk Access in System Preferences → Privacy & Security.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Browse Files")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            openFilePicker()
        }
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
        // Stop security-scoped access before removing
        if file.securityAccessActive {
            file.url.stopAccessingSecurityScopedResource()
        }
        appState.queuedFiles.removeAll { $0.id == file.id }
    }

    private func clearQueue() {
        // Stop security-scoped access for all files
        for file in appState.queuedFiles where file.securityAccessActive {
            file.url.stopAccessingSecurityScopedResource()
        }
        appState.queuedFiles.removeAll()
        appState.taggingProgress = 0.0
    }

    private func startTagging() {
        appState.isTagging = true
        appState.taggingProgress = 0.0

        for index in appState.queuedFiles.indices {
            appState.queuedFiles[index].status = .pending
            appState.queuedFiles[index].error = nil
        }

        taggingTask = Task {
            await performTagging()
        }
    }

    private func cancelTagging() {
        taggingTask?.cancel()
        taggingTask = nil

        appState.isTagging = false
        appState.taggingProgress = 0.0

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

        // Use the tagging engine from AppState (already initialized with models)
        guard let engine = appState.taggingEngine else {
            await MainActor.run {
                appState.isTagging = false
                appState.showToast("No tagging engine available. Please load a model first.", kind: .error)
            }
            return
        }

        let id3Manager = ID3Manager()
        let overwrite = appState.taggingPreferences.overwrite

        for (index, file) in appState.queuedFiles.enumerated() {
            if Task.isCancelled { break }

            await MainActor.run {
                if index < appState.queuedFiles.count {
                    appState.queuedFiles[index].status = .processing
                }
            }

            // Ensure security-scoped access is active
            // Files from folder bookmarks rely on the parent folder's active access.
            let hasFolderAccess = appState.bookmarkManager.hasAccess(to: file.url)
            var startedFileAccess = false
            var mutableFile = file

            if hasFolderAccess {
                print("TaggingView: using folder-scoped access for \(file.url.path)")
            } else {
                startedFileAccess = mutableFile.startAccess()
                print("TaggingView: started file access: \(startedFileAccess) for \(file.url.path)")
            }

            // Defer cleanup to after ALL file operations complete (end of for loop iteration)
            defer {
                if startedFileAccess {
                    print("TaggingView: stopping file access for \(file.url.path)")
                    mutableFile.stopAccess()
                    Task { @MainActor in
                        if index < appState.queuedFiles.count {
                            appState.queuedFiles[index].securityAccessActive = false
                        }
                    }
                }
            }

            let hasAccess = hasFolderAccess || startedFileAccess

            guard hasAccess else {
                await MainActor.run {
                    if index < appState.queuedFiles.count {
                        appState.queuedFiles[index].status = .error
                        appState.queuedFiles[index].error = "Permission denied. Use 'Browse Files' to grant access."
                    }
                }
                await MainActor.run {
                    appState.taggingProgress = Double(index + 1) / Double(totalFiles)
                }
                continue
            }

            do {
                let result = try await engine.analyze(url: file.url)

                var tagsToWrite = TagsToWrite(overwrite: overwrite)
                var writtenTags = AppState.WrittenTags()

                if let user = result.userPredictions {
                    tagsToWrite.genre = user.genre
                    tagsToWrite.timing = user.timing
                    tagsToWrite.mood = user.mood
                    if !user.descriptive.isEmpty {
                        tagsToWrite.comments = user.descriptive.joined(separator: ", ")
                    }

                    writtenTags.userGenre = user.genre
                    writtenTags.userTiming = user.timing
                    writtenTags.userMood = user.mood
                    writtenTags.userDescriptive = user.descriptive
                }

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

                // Sub Genre - use Essentia's top genre prediction
                if appState.taggingPreferences.subGenre.enabled, let subGenre = essentia.topSubGenre {
                    tagsToWrite.subGenre = subGenre
                    writtenTags.essentiaSubGenre = subGenre
                }

                try await id3Manager.writeTags(tagsToWrite, to: file.url)

                await MainActor.run {
                    if index < appState.queuedFiles.count {
                        appState.queuedFiles[index].status = .complete
                        appState.queuedFiles[index].writtenTags = writtenTags
                    }
                    lastTaggingResult = result
                }

            } catch {
                await MainActor.run {
                    if index < appState.queuedFiles.count {
                        appState.queuedFiles[index].status = .error
                        appState.queuedFiles[index].error = error.localizedDescription
                    }
                }
            }

            await MainActor.run {
                appState.taggingProgress = Double(index + 1) / Double(totalFiles)
            }
        }

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
