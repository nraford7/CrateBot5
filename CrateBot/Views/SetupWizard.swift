import SwiftUI
import CrateBotCore
import UniformTypeIdentifiers
import AppKit

struct SetupWizard: View {
    @Environment(AppState.self) private var appState
    @State private var step: Step = .welcome
    @State private var selectedFolders: [URL] = []
    @State private var isSelectingFolder = false

    enum Step: Int, CaseIterable {
        case welcome
        case musicFolders
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Theme.Colors.accentPrimary : Theme.Colors.textTertiary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 40)

            Spacer()

            // Content
            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .musicFolders:
                    musicFoldersStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: 500)

            Spacer()

            // Navigation
            HStack {
                if step != .welcome {
                    Button("Back") {
                        withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Spacer()

                Button(step == .complete ? "Get Started" : "Continue") {
                    if step == .complete {
                        finishSetup()
                    } else {
                        withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .complete }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(step == .musicFolders && selectedFolders.isEmpty)
            }
            .padding(40)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Theme.Colors.bgWindow)
    }

    private var welcomeStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.accentPrimary)

            Text("Welcome to CrateBot")
                .font(Theme.Fonts.heading(28))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Auto-tag your music library using machine learning. Let's get set up.")
                .font(Theme.Fonts.body(16))
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var musicFoldersStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(Theme.Colors.accentPrimary)

            Text("Add Music Folders")
                .font(Theme.Fonts.heading(24))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Select folders containing your MP3 files. CrateBot will remember access to these folders.")
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(selectedFolders, id: \.absoluteString) { url in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Theme.Colors.accentPrimary)
                        Text(url.lastPathComponent)
                            .font(Theme.Fonts.mono(13))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Button {
                            selectedFolders.removeAll { $0 == url }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.bgSurface)
                    .cornerRadius(Theme.Radius.sm)
                }
            }
            .frame(maxWidth: 400)

            Button {
                selectFolder()
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var completeStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.statusSuccess.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.Colors.statusSuccess)
            }

            Text("You're All Set!")
                .font(Theme.Fonts.heading(24))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("CrateBot is ready to tag your music. Drop files onto the app or use the Add Files button to get started.")
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if !selectedFolders.contains(url) {
                selectedFolders.append(url)
            }
        }
    }

    private func finishSetup() {
        // Save bookmarks for selected folders
        for url in selectedFolders {
            try? appState.bookmarkManager.addFolderAccess(url)
        }

        appState.setupComplete = true
    }
}

#Preview {
    SetupWizard()
        .environment(AppState())
}
