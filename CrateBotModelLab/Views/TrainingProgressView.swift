import SwiftUI

struct TrainingProgressView: View {
    @Environment(ModelLabState.self) private var labState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status header
            HStack {
                statusIcon

                VStack(alignment: .leading) {
                    Text(statusTitle)
                        .font(.headline)

                    Text(labState.trainingPhase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if labState.trainingStatus == .running {
                    Button("Cancel") {
                        labState.trainingStatus = .cancelled
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Progress bar
            if labState.trainingStatus == .running || labState.trainingStatus == .paused {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: labState.trainingProgress)

                    HStack {
                        Text("\(labState.filesProcessed) / \(labState.totalFiles) files")
                            .font(.caption)

                        Spacer()

                        Text("\(Int(labState.trainingProgress * 100))%")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Stats
            HStack(spacing: 24) {
                StatBox(title: "Samples", value: "\(labState.samplesCollected)")
                StatBox(title: "Files", value: "\(labState.filesProcessed)")

                if let start = labState.startTime {
                    StatBox(title: "Time", value: formatDuration(since: start))
                }
            }

            // Console
            TrainingConsole()
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var statusIcon: some View {
        Group {
            switch labState.trainingStatus {
            case .running:
                ProgressView()
                    .scaleEffect(0.8)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.orange)
            default:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
    }

    private var statusTitle: String {
        switch labState.trainingStatus {
        case .idle: return "Ready"
        case .scanning: return "Scanning..."
        case .running: return "Training..."
        case .paused: return "Paused"
        case .completed: return "Training Complete"
        case .failed: return "Training Failed"
        case .cancelled: return "Training Cancelled"
        }
    }

    private func formatDuration(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var state = ModelLabState()

    TrainingProgressView()
        .environment(state)
        .onAppear {
            state.trainingStatus = .running
            state.trainingPhase = "Extracting features"
            state.trainingProgress = 0.35
            state.filesProcessed = 35
            state.totalFiles = 100
            state.samplesCollected = 1250
            state.startTime = Date().addingTimeInterval(-125)
        }
}
