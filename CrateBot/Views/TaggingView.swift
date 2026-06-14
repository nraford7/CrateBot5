import SwiftUI
import CrateBotCore
import UniformTypeIdentifiers
import AppKit
import os.log

private let logger = Logger(subsystem: "com.cratebot", category: "TaggingView")

struct TaggingView: View {
    @Environment(AppState.self) private var appState
    @State private var isDropTargeted = false
    @State private var taggingTask: Task<Void, Never>?
    @State private var lastTaggingResult: TaggingResult?
    @State private var showResultsSheet = false
    @State private var showTaggingSettings = false
    @State private var taggingStartTime: Date?

    var body: some View {
        VStack(spacing: 0) {
            // Drop zone or file queue
            if appState.queuedFiles.isEmpty {
                dropZoneView
            } else {
                fileQueueView

                // Bottom controls (only when files are queued)
                controlsBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.bgWindow)
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        ZStack {
            // Background with subtle gradient
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.Colors.bgSurface,
                            Theme.Colors.bgElevated.opacity(0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Dashed border
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .strokeBorder(
                    isDropTargeted ? Theme.Colors.accentPrimary : Theme.Colors.textTertiary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 2, dash: [10, 6])
                )

            // Glow effect when dropping
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.xl)
                    .fill(Theme.Colors.accentPrimary.opacity(0.08))
                    .shadow(color: Theme.Shadows.glowAmber.opacity(0.3), radius: 20)
            }

            VStack(spacing: Theme.Spacing.lg) {
                // Animated vinyl icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Colors.accentLight.opacity(0.2), Theme.Colors.accentPrimary.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            isDropTargeted
                                ? LinearGradient(colors: [Theme.Colors.accentLight, Theme.Colors.accentPrimary], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Theme.Colors.textTertiary, Theme.Colors.textTertiary.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        )
                        .rotationEffect(.degrees(isDropTargeted ? 45 : 0))
                        .animation(.easeInOut(duration: 0.3), value: isDropTargeted)
                }
                .scaleEffect(isDropTargeted ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.2), value: isDropTargeted)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Drop MP3 Files Here")
                        .font(Theme.Fonts.heading(22))
                        .foregroundColor(isDropTargeted ? Theme.Colors.accentPrimary : Theme.Colors.textPrimary)

                    Text("Or drag folders to add all MP3s")
                        .font(Theme.Fonts.body(14))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Button {
                    openFilePicker()
                } label: {
                    Label("Browse Files", systemImage: "folder.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.Spacing.xs)
            }
            .slideUpAnimation()
        }
        .padding(Theme.Spacing.xl)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - File Queue

    private var fileQueueView: some View {
        VStack(spacing: 0) {
            // Status dashboard (always visible when files are queued)
            taggingStatusDashboard

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
        VStack(spacing: 0) {
            // Action buttons bar
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
                    // Pause/Resume button
                    Button {
                        appState.isTaggingPaused.toggle()
                    } label: {
                        Label(appState.isTaggingPaused ? "Resume" : "Pause", systemImage: appState.isTaggingPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Cancel") {
                        cancelTagging()
                    }
                    .buttonStyle(DangerButtonStyle())
                } else {
                    startTaggingButton
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)
        }
    }

    // MARK: - Tagging Status Dashboard (VU Meter Style)

    private var statusLabel: String {
        if !appState.isTagging {
            return "READY"
        } else if appState.isTaggingPaused {
            return "PAUSED"
        } else {
            return "TAGGING"
        }
    }

    private var statusLEDColor: Color {
        if !appState.isTagging {
            return Theme.Colors.accentPrimary
        } else if appState.isTaggingPaused {
            return Theme.Colors.statusWarning
        } else {
            return Theme.Colors.statusSuccess
        }
    }

    private var taggingStatusDashboard: some View {
        let completedCount = appState.queuedFiles.filter { $0.status == .complete }.count
        let errorCount = appState.queuedFiles.filter { $0.status == .error }.count
        let totalCount = appState.queuedFiles.count

        return VStack(spacing: 0) {
            // Top gradient accent line
            LinearGradient(
                colors: [Theme.Colors.accentPrimary, Theme.Colors.accentLight, Theme.Colors.accentPrimary],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 2)
            .shadow(color: Theme.Shadows.glowAmber.opacity(0.5), radius: 4)

            VStack(spacing: Theme.Spacing.md) {
                // Status header with LED indicator
                HStack(spacing: Theme.Spacing.sm) {
                    // Status LED
                    Circle()
                        .fill(statusLEDColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusLEDColor.opacity(0.6), radius: 6)
                        .scaleEffect(appState.isTagging && !appState.isTaggingPaused ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: appState.isTagging && !appState.isTaggingPaused)

                    Text(statusLabel)
                        .font(Theme.Fonts.mono(11))
                        .fontWeight(.bold)
                        .foregroundColor(statusLEDColor)
                        .tracking(1.5)

                    Spacer()
                }

                // VU Meter style stats row
                HStack(spacing: Theme.Spacing.sm) {
                    // Progress meter
                    VUMeterStat(
                        label: "PROGRESS",
                        value: "\(completedCount)/\(totalCount)",
                        progress: appState.taggingProgress,
                        color: Theme.Colors.accentPrimary
                    )

                    // Completed meter (percentage)
                    VUMeterStat(
                        label: "COMPLETE",
                        value: "\(Int(appState.taggingProgress * 100))%",
                        progress: appState.taggingProgress,
                        color: Theme.Colors.statusSuccess
                    )

                    // Errors meter
                    VUMeterStat(
                        label: "ERRORS",
                        value: "\(errorCount)",
                        progress: totalCount > 0 ? Double(errorCount) / Double(totalCount) : 0,
                        color: errorCount > 0 ? Theme.Colors.statusError : Theme.Colors.textTertiary
                    )

                    // Time stats (with placeholder progress for consistent height)
                    VUMeterStat(
                        label: "SPEED",
                        value: calculateAverageTime(),
                        progress: 0,
                        color: Theme.Colors.accentSecondary,
                        showMeter: false
                    )

                    // ETA (with placeholder progress for consistent height)
                    VUMeterStat(
                        label: "ETA",
                        value: calculateETA(),
                        progress: 0,
                        color: Theme.Colors.accentPrimary,
                        isHighlighted: true,
                        showMeter: false
                    )
                }

                // Main progress bar with LED VU meter
                VStack(spacing: 4) {
                    LEDProgressBar(
                        progress: appState.taggingProgress,
                        isAnimating: appState.isTagging && !appState.isTaggingPaused,
                        segmentCount: 20,
                        height: 10
                    )

                    // Secondary amber progress indicator (subtle)
                    ThemedProgressBar(progress: appState.taggingProgress, isAnimating: appState.isTagging && !appState.isTaggingPaused, height: 4)
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                LinearGradient(
                    colors: [Theme.Colors.bgElevated, Theme.Colors.bgSurface],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // Time calculations
    private func calculateAverageTime() -> String {
        let completedCount = appState.queuedFiles.filter { $0.status == .complete }.count
        guard completedCount > 0, let startTime = taggingStartTime else { return "-" }
        let elapsed = Date().timeIntervalSince(startTime)
        let avg = elapsed / Double(completedCount)
        return String(format: "%.1fs", avg)
    }

    private func calculateETA() -> String {
        let completedCount = appState.queuedFiles.filter { $0.status == .complete }.count
        let remainingCount = appState.queuedFiles.count - completedCount
        guard completedCount > 0, let startTime = taggingStartTime else { return "-" }
        let elapsed = Date().timeIntervalSince(startTime)
        let avgPerFile = elapsed / Double(completedCount)
        let remaining = Double(remainingCount) * avgPerFile

        if remaining < 60 {
            return "\(Int(remaining))s"
        } else if remaining < 3600 {
            let minutes = Int(remaining / 60)
            let secs = Int(remaining.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
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
                    logger.warning("Failed to bookmark folder: \(error.localizedDescription)")
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
        appState.isTaggingPaused = false
        taggingStartTime = Date()

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
        appState.isTaggingPaused = false
        taggingStartTime = nil

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

        // AI-description (VibeGeneratorV2) setup. Hoisted out of the per-track
        // loop so the cache + cooccurrence stats load once, not 50 times.
        // The whole block is gated by the opt-in toggle AND the keychain check;
        // when off, the rest of the pass behaves exactly as before.
        let aiDescriptionsEnabled =
            appState.taggingPreferences.aiDescriptions.enabled
            && KeychainManager.shared.exists(key: .anthropicAPIKey)
        let vibeCache: VibeCache? = aiDescriptionsEnabled ? VibeCache() : nil
        let vibeGenerator: VibeGeneratorV2? = aiDescriptionsEnabled
            ? VibeGeneratorV2(client: AnthropicVibeChatClient(client: AnthropicClient()))
            : nil
        let cooccurrenceStats: Cooccurrence.Stats? = aiDescriptionsEnabled
            ? Cooccurrence.loadFromBundle()
            : nil
        let stage1Version = aiDescriptionsEnabled
            ? (await engine.stage1ModelVersion ?? "unknown")
            : "unused"

        for (index, file) in appState.queuedFiles.enumerated() {
            if Task.isCancelled { break }

            // Wait while paused (check on MainActor since AppState is @Observable)
            var isPaused = await MainActor.run { appState.isTaggingPaused }
            while isPaused && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                isPaused = await MainActor.run { appState.isTaggingPaused }
            }
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
                logger.debug("Using folder-scoped access for \(file.url.path)")
            } else {
                startedFileAccess = mutableFile.startAccess()
                logger.debug("Started file access: \(startedFileAccess) for \(file.url.path)")
            }

            // Defer cleanup to after ALL file operations complete (end of for loop iteration)
            defer {
                if startedFileAccess {
                    logger.debug("Stopping file access for \(file.url.path)")
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

                // Load user's field mapping configuration to write tags to correct ID3 frames
                let tagMappingConfig = TagMappingConfiguration.load()
                var tagsToWrite = TagsToWrite(overwrite: overwrite, fieldMapping: tagMappingConfig.writeMapping)
                tagsToWrite.preventAcapellaGenre = shouldPreventAcapellaGenre(result: result)
                var writtenTags = AppState.WrittenTags()
                var aiDescriptionError: String?

                if let user = result.userPredictions {
                    let genre = allowedGenre(user.genre, preventAcapellaGenre: tagsToWrite.preventAcapellaGenre)
                    tagsToWrite.genre = genre
                    tagsToWrite.timing = user.timing
                    tagsToWrite.mood = user.mood
                    if !user.descriptive.isEmpty {
                        tagsToWrite.comments = user.descriptive.joined(separator: ", ")
                    }

                    writtenTags.userGenre = genre
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

                // AI descriptions (VibeGeneratorV2). Cache-first when a stable
                // Stage 1 model version is available; on miss call the LLM;
                // on success populate all three vibe fields atomically.
                // On error, clear stale AI frames and mark the row as errored so
                // legacy Composer/Description values cannot look freshly generated.
                if aiDescriptionsEnabled, let generator = vibeGenerator {
                    tagsToWrite.clearVibeFields = true
                    let trackPath = file.url.path
                    // Skip the cache when stage1ModelVersion is unknown — bucketing
                    // distinct loaded models under a sentinel string would leak
                    // stale vibes across model swaps. The LLM call still runs.
                    let cacheUsable = vibeCache != nil && !stage1Version.isEmpty && stage1Version != "unknown"
                    if cacheUsable, let cache = vibeCache,
                       let cached = await cache.get(trackPath: trackPath, stage1ModelVersion: stage1Version),
                       let cachedMixHint = cached.mixHint {
                        tagsToWrite.vibeShort = cached.short
                        tagsToWrite.vibeDescription = cached.long
                        tagsToWrite.mixHint = cachedMixHint
                    } else {
                        let cooccurrence: CooccurrenceContext?
                        if let stats = cooccurrenceStats, let timing = result.timingPrediction?.label {
                            cooccurrence = Cooccurrence.context(timing: timing, stats: stats)
                        } else {
                            cooccurrence = nil
                        }
                        let userPreds = result.userPredictions
                            ?? UserTagPredictions(genre: nil, timing: nil, mood: nil, descriptive: [])
                        // Read title/artist for grounding inputs. Cheap because the
                        // ID3 read is local; spec lists both as generator inputs.
                        let extracted = try? id3Manager.readTags(from: file.url)
                        let inputs = VibeGenerationInputs(
                            binaryConfidences: result.binaryConfidences,
                            groupProbabilities: result.groupProbabilities,
                            predictedTags: userPreds,
                            bpm: result.bpm,
                            key: nil,
                            durationSeconds: result.durationSeconds,
                            title: extracted?.title,
                            artist: extracted?.artist,
                            album: extracted?.album,
                            stage2Timing: result.timingPrediction,
                            cooccurrence: cooccurrence
                        )
                        do {
                            let generated = try await generator.generate(inputs: inputs)
                            tagsToWrite.vibeShort = generated.short
                            tagsToWrite.vibeDescription = generated.long
                            tagsToWrite.mixHint = generated.mixHint
                            if cacheUsable, let cache = vibeCache {
                                await cache.set(
                                    generated,
                                    trackPath: trackPath,
                                    stage1ModelVersion: stage1Version
                                )
                            }
                        } catch {
                            aiDescriptionError = "AI descriptions failed; stale AI fields cleared. \(error.localizedDescription)"
                            logger.warning("Vibe generation failed for \(file.url.lastPathComponent): \(error.localizedDescription) — stale vibe fields cleared")
                        }
                    }
                }

                try await id3Manager.writeTags(tagsToWrite, to: file.url)

                await MainActor.run {
                    if index < appState.queuedFiles.count {
                        appState.queuedFiles[index].status = aiDescriptionError == nil ? .complete : .error
                        appState.queuedFiles[index].error = aiDescriptionError
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

    private func shouldPreventAcapellaGenre(result: TaggingResult) -> Bool {
        if result.essentiaTags.instruments.contains(where: isNonVocalMusicSignal) {
            return true
        }
        guard let user = result.userPredictions else {
            return false
        }
        if let genre = user.genre, !isAcapellaGenre(genre) {
            return true
        }
        return user.bassType != nil
            || !user.rhythm.isEmpty
            || !user.style.isEmpty
            || !user.instruments.isEmpty
    }

    private func allowedGenre(_ genre: String?, preventAcapellaGenre: Bool) -> String? {
        guard let genre else { return nil }
        if preventAcapellaGenre && isAcapellaGenre(genre) {
            return nil
        }
        return genre
    }

    private func isAcapellaGenre(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Acapella") == .orderedSame
    }

    private func isNonVocalMusicSignal(_ name: String) -> Bool {
        let lower = name.lowercased()
        return !lower.contains("voice")
            && !lower.contains("vocal")
            && !lower.contains("acapella")
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
