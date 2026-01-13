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
            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
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
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(step == .complete ? "Get Started" : "Continue") {
                    if step == .complete {
                        finishSetup()
                    } else {
                        withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .complete }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == .musicFolders && selectedFolders.isEmpty)
            }
            .padding(40)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to CrateBot")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Auto-tag your music library using machine learning. Let's get set up.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var musicFoldersStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(Color.accentColor)

            Text("Add Music Folders")
                .font(.title)
                .fontWeight(.bold)

            Text("Select folders containing your MP3 files. CrateBot will remember access to these folders.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(selectedFolders, id: \.absoluteString) { url in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(url.lastPathComponent)
                        Spacer()
                        Button {
                            selectedFolders.removeAll { $0 == url }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                }
            }
            .frame(maxWidth: 400)

            Button {
                selectFolder()
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
        }
    }

    private var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("CrateBot is ready to tag your music. Drop files onto the app or use the Add Files button to get started.")
                .foregroundStyle(.secondary)
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
