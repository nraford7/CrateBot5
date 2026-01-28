import SwiftUI
import AppKit
import CrateBotCore

struct SettingsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    strictnessSection
                    taggingOptionsSection
                    fallbackMappingsSection
                    musicFoldersSection
                    modelSection
                    aboutSection
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.bgWindow)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        appState.taggingPreferences.save()
                        Task {
                            await appState.saveFallbackMappings()
                            await appState.syncTaggingPreferences()
                        }
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .frame(minWidth: 550, minHeight: 500)
    }

    // MARK: - Strictness Section

    private var strictnessSection: some View {
        @Bindable var appState = appState

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Tagging Strictness")

            VStack(spacing: Theme.Spacing.sm) {
                Picker("Strictness", selection: $appState.taggingPreferences.strictness) {
                    ForEach(TaggingStrictness.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(appState.taggingPreferences.strictness.description)
                    .font(Theme.Fonts.body(12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.md)

            Text("Controls the confidence threshold for applying tags. Lower values apply more tags but may include uncertain matches. Essentia predictions are used to validate low-confidence tags.")
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    // MARK: - Tagging Options Section

    private var taggingOptionsSection: some View {
        @Bindable var appState = appState

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Tagging Options")

            VStack(spacing: Theme.Spacing.sm) {
                fieldToggleRow(
                    label: "Genre",
                    enabled: $appState.taggingPreferences.genre.enabled,
                    targetField: appState.taggingPreferences.genre.targetField
                )

                fieldToggleRow(
                    label: "Sub Genre",
                    enabled: $appState.taggingPreferences.subGenre.enabled,
                    targetField: appState.taggingPreferences.subGenre.targetField
                )

                fieldToggleRow(
                    label: "Timing",
                    enabled: $appState.taggingPreferences.album.enabled,
                    targetField: appState.taggingPreferences.album.targetField
                )

                fieldToggleRow(
                    label: "Mood",
                    enabled: $appState.taggingPreferences.mood.enabled,
                    targetField: appState.taggingPreferences.mood.targetField
                )

                fieldToggleRow(
                    label: "Comments",
                    enabled: $appState.taggingPreferences.comments.enabled,
                    targetField: appState.taggingPreferences.comments.targetField
                )

                fieldToggleRow(
                    label: "Likeness",
                    enabled: $appState.taggingPreferences.likeness.enabled,
                    targetField: appState.taggingPreferences.likeness.targetField
                )

                fieldToggleRow(
                    label: "Vibes Short",
                    enabled: $appState.taggingPreferences.vibesShort.enabled,
                    targetField: appState.taggingPreferences.vibesShort.targetField
                )

                fieldToggleRow(
                    label: "Vibes Long",
                    enabled: $appState.taggingPreferences.vibesLong.enabled,
                    targetField: appState.taggingPreferences.vibesLong.targetField
                )

                fieldToggleRow(
                    label: "Hooks",
                    enabled: $appState.taggingPreferences.hooks.enabled,
                    targetField: appState.taggingPreferences.hooks.targetField
                )

                Divider().background(Theme.Colors.textTertiary.opacity(0.2))

                HStack {
                    Toggle("Overwrite Existing Tags", isOn: $appState.taggingPreferences.overwrite)
                        .font(Theme.Fonts.body(14))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.md)

            Text("Configure which ID3 fields CrateBot writes to when tagging files.")
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    // MARK: - Fallback Mappings Section

    @State private var showFallbackEditor = false

    private var fallbackMappingsSection: some View {
        @Bindable var appState = appState

        let configuredCount = appState.fallbackMappingConfig.mappings.filter { !$0.essentiaLabels.isEmpty }.count

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Tag Fallback Mappings")

            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Toggle("Enable Fallback Mappings", isOn: $appState.fallbackMappingConfig.enabled)
                        .font(Theme.Fonts.body(14))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.xs)

                if appState.fallbackMappingConfig.enabled {
                    Divider().background(Theme.Colors.textTertiary.opacity(0.2))

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(configuredCount) tags configured")
                                .font(Theme.Fonts.body(14))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("Map model tags to Essentia predictions")
                                .font(Theme.Fonts.body(12))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }

                        Spacer()

                        Button {
                            showFallbackEditor = true
                        } label: {
                            Label("Edit Mappings", systemImage: "pencil")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(appState.loadedTagNames.isEmpty)
                    }
                    .padding(.vertical, Theme.Spacing.xs)

                    if appState.loadedTagNames.isEmpty {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "info.circle")
                                .foregroundColor(Theme.Colors.textTertiary)
                            Text("Load a model to configure fallback mappings")
                                .font(Theme.Fonts.body(12))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.md)

            Text("Fallback mappings apply Essentia predictions when your trained classifiers have low confidence. Uses the global strictness threshold.")
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .sheet(isPresented: $showFallbackEditor) {
            FallbackMappingsEditor()
                .environment(appState)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.heading(16))
            .foregroundColor(Theme.Colors.textPrimary)
    }

    private func fieldToggleRow(label: String, enabled: Binding<Bool>, targetField: String) -> some View {
        HStack {
            Toggle(label, isOn: enabled)
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            if enabled.wrappedValue {
                Text(targetField)
                    .font(Theme.Fonts.mono(11))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.bgElevated)
                    .cornerRadius(Theme.Radius.sm)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Music Folders Section

    private var musicFoldersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Music Folders")

            VStack(spacing: Theme.Spacing.sm) {
                if appState.bookmarkManager.musicFolderURLs.isEmpty {
                    Text("No folders added")
                        .font(Theme.Fonts.body(14))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.md)
                } else {
                    ForEach(appState.bookmarkManager.musicFolderURLs, id: \.absoluteString) { url in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.Colors.accentPrimary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(Theme.Fonts.body(14))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(Theme.Fonts.mono(11))
                                    .foregroundColor(Theme.Colors.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                removeFolder(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove folder")
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }

                Button {
                    addFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.md)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.message = "Select a folder containing your music files"
        panel.prompt = "Add Folder"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try appState.bookmarkManager.addFolderAccess(url)
            } catch {
                appState.showToast("Failed to add folder: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    private func removeFolder(_ url: URL) {
        appState.bookmarkManager.removeFolderAccess(url)
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Model")

            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Status")
                        .font(Theme.Fonts.body(14))
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer()
                    HStack(spacing: Theme.Spacing.sm) {
                        StatusLED(
                            status: appState.modelLoaded ? .complete : .pending,
                            size: 8
                        )
                        Text(appState.modelLoaded ? "Loaded" : "Not Loaded")
                            .font(Theme.Fonts.body(14))
                            .foregroundColor(appState.modelLoaded ? Theme.Colors.statusSuccess : Theme.Colors.textTertiary)
                    }
                }

                if let modelName = appState.modelName {
                    HStack {
                        Text("Model")
                            .font(Theme.Fonts.body(14))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text(modelName)
                            .font(Theme.Fonts.mono(14))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }

                if appState.availableTags != nil {
                    HStack {
                        Text("Tags Available")
                            .font(Theme.Fonts.body(14))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Colors.statusSuccess)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.md)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("About")

            VStack(spacing: Theme.Spacing.sm) {
                aboutRow("Version", value: appVersion)
                aboutRow("CrateBotCore", value: CrateBotCore.version)
                aboutRow("Build", value: buildNumber)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.md)
        }
    }

    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Fonts.mono(14))
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Previews

#Preview("Settings Panel") {
    @Previewable @State var previewState = AppState()

    SettingsPanel()
        .environment(previewState)
        .onAppear {
            previewState.modelLoaded = true
            previewState.modelName = "CrateBotModel_v2"
        }
}

#Preview("Settings - Empty Folders") {
    SettingsPanel()
        .environment(AppState())
}

#Preview("Settings - With Folders") {
    @Previewable @State var previewState = AppState()

    SettingsPanel()
        .environment(previewState)
        .onAppear {
            previewState.modelLoaded = true
            previewState.modelName = "CrateBotModel_v2"
            previewState.availableTags = AppState.AvailableTags(
                genre: ["House", "Techno"],
                timing: ["Intro", "Drop"],
                mood: ["Upbeat", "Mellow"],
                descriptive: ["Vocal", "Instrumental"]
            )
        }
}

#Preview("Settings - Model Not Loaded") {
    @Previewable @State var previewState = AppState()

    SettingsPanel()
        .environment(previewState)
        .onAppear {
            previewState.modelLoaded = false
            previewState.modelName = nil
        }
}
