import SwiftUI

struct TrainingConsole: View {
    @Environment(ModelLabState.self) private var labState
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Console")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Button {
                    labState.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(labState.logs) { entry in
                            logEntryView(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: labState.logs.count) { _, _ in
                    if autoScroll, let last = labState.logs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 150)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func logEntryView(_ entry: ModelLabState.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatTime(entry.timestamp))
                .foregroundStyle(.secondary)

            Text(entry.level.rawValue.uppercased())
                .foregroundStyle(colorForLevel(entry.level))
                .frame(width: 50, alignment: .leading)

            Text(entry.message)
                .foregroundStyle(.white)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func colorForLevel(_ level: ModelLabState.LogEntry.Level) -> Color {
        switch level {
        case .info: return .cyan
        case .warning: return .yellow
        case .error: return .red
        }
    }
}

#Preview {
    @Previewable @State var state = ModelLabState()

    TrainingConsole()
        .environment(state)
        .padding()
        .onAppear {
            state.addLog("Starting training...")
            state.addLog("Loading audio files")
            state.addLog("Processing file: track001.mp3")
            state.addLog("Warning: Skipping corrupt file", level: .warning)
            state.addLog("Extracted 512 features")
        }
}
