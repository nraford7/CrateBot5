import SwiftUI
import AppKit
import CrateBotCore

struct SettingsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        // No NavigationStack: on macOS it reserves leading space for navigation
        // chrome that doesn't render in a sheet, clipping the first ~10px of
        // each section header. A flat VStack with a manual title bar and a
        // bottom toolbar gives the same visual without the clip.
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(Theme.Fonts.heading(20))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.bgWindow)

            Divider()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    strictnessSection
                    taggingOptionsSection
                    fallbackMappingsSection
                    connectionsSection
                    musicFoldersSection
                    modelSection
                    aboutSection
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Colors.bgWindow)

            Divider()

            HStack {
                Spacer()
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
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.bgWindow)
        }
        .frame(minWidth: 620, idealWidth: 660, maxWidth: 720, minHeight: 560, idealHeight: 720)
        .background(Theme.Colors.bgWindow)
    }

    // MARK: - Strictness Section

    private var strictnessSection: some View {
        @Bindable var appState = appState

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Tagging Strictness")

            VStack(spacing: Theme.Spacing.sm) {
                strictnessControl

                Text(appState.taggingPreferences.strictness.description)
                    .font(Theme.Fonts.body(12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.md)

            Text("Shifts each tag category's default confidence threshold up or down. Looser settings apply more tags but may include uncertain matches. Essentia predictions are used to validate low-confidence tags.")
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var strictnessControl: some View {
        @Bindable var appState = appState

        return HStack(spacing: 2) {
            ForEach(TaggingStrictness.allCases, id: \.self) { level in
                let selected = appState.taggingPreferences.strictness == level
                Button {
                    appState.taggingPreferences.strictness = level
                    Task {
                        await appState.syncTaggingPreferences()
                    }
                } label: {
                    Text(strictnessControlLabel(for: level))
                        .font(Theme.Fonts.body(12))
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundColor(selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(selected ? Theme.Colors.accentPrimary.opacity(0.85) : Color.clear)
                )
                .accessibilityLabel(level.displayName)
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func strictnessControlLabel(for level: TaggingStrictness) -> String {
        switch level {
        case .loose: return "Loose -15%"
        case .average: return "Balanced"
        case .strict: return "Strict +15%"
        case .veryStrict: return "Very Strict +25%"
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

                let hasAnthropicKey = KeychainManager.shared.exists(key: .anthropicAPIKey)
                fieldToggleRow(
                    label: "AI Descriptions",
                    enabled: $appState.taggingPreferences.aiDescriptions.enabled,
                    targetField: appState.taggingPreferences.aiDescriptions.targetField
                )
                .disabled(!hasAnthropicKey)
                .help(hasAnthropicKey
                      ? "Generates short vibe, prose description, and DJ mix-context hint per track via Anthropic API. ~$0.01-$0.02/track at current Sonnet 4 pricing."
                      : "Set the Anthropic API key in Connections (below) to enable.")
                if !hasAnthropicKey {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("Set Anthropic API key in Connections (below) to enable.")
                            .font(Theme.Fonts.body(11))
                    }
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.leading, Theme.Spacing.lg)
                    .padding(.top, -Theme.Spacing.xs)
                }

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
        .frame(maxWidth: .infinity, alignment: .leading)
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

            Text("Fallback mappings apply Essentia predictions when your trained classifiers have low confidence. Uses each tag's resolved threshold (category default plus strictness).")
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showFallbackEditor) {
            FallbackMappingsEditor()
                .environment(appState)
        }
    }

    // MARK: - Connections Section

    @State private var anthropicKeyDraft: String = ""
    @State private var anthropicKeySaveError: String?

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Connections")

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Anthropic API Key")
                    .font(Theme.Fonts.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)

                let hasKey = KeychainManager.shared.exists(key: .anthropicAPIKey)

                HStack(spacing: Theme.Spacing.sm) {
                    SecureField(hasKey ? "Stored — enter a new value to replace" : "sk-ant-...", text: $anthropicKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.mono(12))

                    Button("Save") {
                        anthropicKeySaveError = nil
                        do {
                            try appState.setAnthropicAPIKey(anthropicKeyDraft)
                            anthropicKeyDraft = ""
                        } catch {
                            anthropicKeySaveError = error.localizedDescription
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(anthropicKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasKey {
                        Button("Remove") {
                            anthropicKeySaveError = nil
                            do {
                                try appState.setAnthropicAPIKey(nil)
                            } catch {
                                anthropicKeySaveError = error.localizedDescription
                            }
                        }
                    }
                }

                if hasKey {
                    Text("Key stored locally for this app.")
                        .font(Theme.Fonts.body(12))
                        .foregroundColor(Theme.Colors.textTertiary)
                } else {
                    Text("Required for AI Descriptions. Stored locally for this app; sent only to Anthropic.")
                        .font(Theme.Fonts.body(12))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = anthropicKeySaveError {
                    Text(error)
                        .font(Theme.Fonts.body(12))
                        .foregroundColor(Theme.Colors.statusError)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.md)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.heading(16))
            .foregroundColor(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.bgElevated)
                    .cornerRadius(Theme.Radius.sm)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity)
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
