import SwiftUI
import CrateBotCore
import AppKit

struct StatusBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Model status (clickable to load model)
            Button {
                loadModelFromDialog()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if appState.isLoadingModel {
                        // Show loading percentage
                        Text("Loading \(Int(appState.modelLoadingProgress * 100))%")
                            .font(Theme.Fonts.mono(12))
                            .foregroundColor(Theme.Colors.accentPrimary)
                    } else {
                        StatusLED(
                            status: appState.modelLoaded ? .complete : .pending,
                            size: 8
                        )

                        if let name = appState.modelName {
                            Text(name)
                                .font(Theme.Fonts.mono(12))
                                .foregroundColor(Theme.Colors.textPrimary)
                        } else {
                            Text("No model loaded")
                                .font(Theme.Fonts.body(12))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.bgSurface)
                .cornerRadius(Theme.Radius.sm)
            }
            .buttonStyle(.plain)
            .disabled(appState.isLoadingModel)
            .help(appState.isLoadingModel ? "Loading model..." : "Click to load a different model")

            Spacer()

            // Version
            Text("v1.0.0")
                .font(Theme.Fonts.mono(11))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.bgElevated)
    }

    private func loadModelFromDialog() {
        // Get models directory first (synchronously since ModelManager uses FileManager)
        let modelsDir = try? ModelManager().modelsDirectory()

        // Open file dialog pointing to models directory
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a trained model directory"
        panel.prompt = "Load Model"

        // Set starting directory to models folder
        if let modelsDir = modelsDir {
            panel.directoryURL = modelsDir
        }

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await appState.loadModel(from: url)
                    appState.showToast("Model '\(appState.modelName ?? "Unknown")' loaded")
                } catch {
                    appState.showToast("Failed to load model: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }
}

#Preview {
    StatusBar()
        .environment(AppState())
}
