import SwiftUI
import AppKit
import CrateBotCore

struct SettingsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            Form {
                taggingOptionsSection
                musicFoldersSection
                modelSection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        appState.taggingPreferences.save()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 550, minHeight: 500)
    }

    // MARK: - Tagging Options Section

    private var taggingOptionsSection: some View {
        @Bindable var appState = appState

        return Section {
            // Genre
            fieldToggleRow(
                label: "Genre",
                enabled: $appState.taggingPreferences.genre.enabled,
                targetField: appState.taggingPreferences.genre.targetField
            )

            // Album
            fieldToggleRow(
                label: "Album",
                enabled: $appState.taggingPreferences.album.enabled,
                targetField: appState.taggingPreferences.album.targetField
            )

            // Mood
            fieldToggleRow(
                label: "Mood",
                enabled: $appState.taggingPreferences.mood.enabled,
                targetField: appState.taggingPreferences.mood.targetField
            )

            // Comments
            fieldToggleRow(
                label: "Comments",
                enabled: $appState.taggingPreferences.comments.enabled,
                targetField: appState.taggingPreferences.comments.targetField
            )

            // Likeness
            fieldToggleRow(
                label: "Likeness",
                enabled: $appState.taggingPreferences.likeness.enabled,
                targetField: appState.taggingPreferences.likeness.targetField
            )

            // Vibes (has two target fields)
            vibesToggleRow

            // Hooks
            fieldToggleRow(
                label: "Hooks",
                enabled: $appState.taggingPreferences.hooks.enabled,
                targetField: appState.taggingPreferences.hooks.targetField
            )

            Divider()

            // Overwrite toggle
            Toggle("Overwrite Existing Tags", isOn: $appState.taggingPreferences.overwrite)
        } header: {
            Text("Tagging Options")
        } footer: {
            Text("Configure which ID3 fields CrateBot writes to when tagging files.")
                .foregroundStyle(.secondary)
        }
    }

    private func fieldToggleRow(label: String, enabled: Binding<Bool>, targetField: String) -> some View {
        HStack {
            Toggle(label, isOn: enabled)

            Spacer()

            if enabled.wrappedValue {
                Text(targetField)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }

    private var vibesToggleRow: some View {
        @Bindable var appState = appState

        return HStack {
            Toggle("Vibes", isOn: $appState.taggingPreferences.vibes.enabled)

            Spacer()

            if appState.taggingPreferences.vibes.enabled {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(appState.taggingPreferences.vibes.shortTargetField)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.taggingPreferences.vibes.longTargetField)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }
        }
    }

    // MARK: - Music Folders Section

    private var musicFoldersSection: some View {
        Section("Music Folders") {
            if appState.bookmarkManager.musicFolderURLs.isEmpty {
                Text("No folders added")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.bookmarkManager.musicFolderURLs, id: \.absoluteString) { url in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            removeFolder(url)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove folder")
                    }
                }
            }

            Button {
                addFolder()
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
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
        Section("Model") {
            HStack {
                Text("Status")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.modelLoaded ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appState.modelLoaded ? "Loaded" : "Not Loaded")
                        .foregroundStyle(.secondary)
                }
            }

            if let modelName = appState.modelName {
                LabeledContent("Model", value: modelName)
            }

            if appState.availableTags != nil {
                HStack {
                    Text("Tags Available")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("CrateBotCore", value: CrateBotCore.version)
            LabeledContent("Build", value: buildNumber)
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
