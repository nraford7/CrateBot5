import AppKit
import SwiftUI

struct TrainingDirectoryCard: View {
    @Environment(ModelLabState.self) private var labState

    var body: some View {
        @Bindable var state = labState

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Training Directory", systemImage: "folder")
                    .font(.headline)

                HStack {
                    TextField("Select a directory with tagged MP3s...", text: Binding(
                        get: { labState.trainingDirectory?.path ?? "" },
                        set: { _ in }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                    Button("Browse") {
                        selectDirectory()
                    }
                    .disabled(labState.trainingStatus != .idle)
                }

                Text("Select a folder containing MP3 files with existing Genre, Timing, Mood, and Comment tags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
        .padding(.horizontal)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK, let url = panel.url {
            labState.trainingDirectory = url
        }
    }
}

#Preview {
    TrainingDirectoryCard()
        .environment(ModelLabState())
}
