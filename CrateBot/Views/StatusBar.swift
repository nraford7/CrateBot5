import SwiftUI
import CrateBotCore

struct StatusBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 16) {
            // Model status
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.modelLoaded ? .green : .orange)
                    .frame(width: 8, height: 8)

                if let name = appState.modelName {
                    Text(name)
                        .font(.caption)
                } else {
                    Text("No model loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .frame(height: 12)

            // Music folders
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                Text("\(appState.bookmarkManager.musicFolderURLs.count) folders")
                    .font(.caption)
            }

            Spacer()

            // Version
            Text("v1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

#Preview {
    StatusBar()
        .environment(AppState())
}
