import SwiftUI
import CrateBotCore
import AppKit

struct StatusBar: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Model status (clickable to load model)
            HStack(spacing: Theme.Spacing.xs) {
                Text("Model:")
                    .font(Theme.Fonts.label(11))
                    .foregroundColor(Theme.Colors.textTertiary)

                Button {
                    loadModelFromDialog()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        if appState.isLoadingModel {
                            // Show loading spinner and percentage
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text("Loading \(Int(appState.modelLoadingProgress * 100))%")
                                .font(Theme.Fonts.mono(11))
                                .foregroundColor(Theme.Colors.accentPrimary)
                        } else {
                            // Model LED indicator
                            Circle()
                                .fill(appState.modelLoaded ? Theme.Colors.statusSuccess : Theme.Colors.textTertiary.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .shadow(color: appState.modelLoaded ? Theme.Colors.statusSuccess.opacity(0.5) : .clear, radius: 4)

                            if let name = appState.modelName {
                                Text(name)
                                    .font(Theme.Fonts.mono(11))
                                    .foregroundColor(isHovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            } else {
                                Text("No model")
                                    .font(Theme.Fonts.body(11))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }

                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(isHovered ? Theme.Colors.bgHover : Theme.Colors.bgSurface)
                    .cornerRadius(Theme.Radius.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.xs)
                            .strokeBorder(isHovered ? Theme.Colors.accentPrimary.opacity(0.3) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.isLoadingModel)
                .onHover { isHovered = $0 }
                .help(appState.isLoadingModel ? "Loading model..." : "Click to load a different model")
                .animation(Theme.Animation.snap, value: isHovered)
            }

            Spacer()

            // Tag count if model loaded
            if appState.modelLoaded && !appState.loadedTagNames.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.Colors.accentPrimary.opacity(0.7))
                    Text("\(appState.loadedTagNames.count) tags")
                        .font(Theme.Fonts.mono(10))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            // Version with subtle branding
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.Colors.accentPrimary)
                    .frame(width: 4, height: 4)
                Text("v1.0.0")
                    .font(Theme.Fonts.mono(10))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            // Settings button
            Button {
                appState.settingsOpen = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.bgElevated)
        .overlay(alignment: .top) {
            Theme.Colors.textTertiary.opacity(0.1)
                .frame(height: 1)
        }
    }

    private func loadModelFromDialog() {
        Task {
            let modelsDir = try? await ModelManager().modelsDirectory()
            let selectedURL: URL? = await MainActor.run {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.message = "Select a trained model directory"
                panel.prompt = "Load Model"

                if let modelsDir = modelsDir {
                    panel.directoryURL = modelsDir
                }

                return panel.runModal() == .OK ? panel.url : nil
            }

            guard let url = selectedURL else { return }

            do {
                try await appState.loadModel(from: url)
                appState.showToast("Model '\(appState.modelName ?? "Unknown")' loaded")
            } catch {
                appState.showToast("Failed to load model: \(error.localizedDescription)", kind: .error)
            }
        }
    }
}

#Preview {
    StatusBar()
        .environment(AppState())
}
