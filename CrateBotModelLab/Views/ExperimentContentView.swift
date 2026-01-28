import SwiftUI
import CrateBotCore

struct ExperimentContentView: View {
    @Environment(ModelLabState.self) private var state
    @State private var selectedView: SidebarItem = .setup

    enum SidebarItem: String, CaseIterable {
        case setup = "Setup"
        case results = "Results"
        case history = "History"
        case export = "Export"

        var icon: String {
            switch self {
            case .setup: return "slider.horizontal.3"
            case .results: return "chart.bar.fill"
            case .history: return "clock.fill"
            case .export: return "square.and.arrow.up"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedView) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)

            // Status footer
            VStack(alignment: .leading, spacing: 4) {
                if state.isExperimentRunning {
                    ProgressView(value: state.experimentProgress?.overallProgress ?? 0)
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let result = state.currentExperiment {
                    Text("Last: \(result.configuration.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Accuracy: \(Int(result.averageAccuracy * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        } detail: {
            switch selectedView {
            case .setup:
                ExperimentSetupView()
            case .results:
                ExperimentResultsView()
            case .history:
                ExperimentHistoryView()
            case .export:
                ExperimentExportView()
            }
        }
        .navigationTitle("Model Lab - Experiments")
        .alert("Error", isPresented: .init(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var progressText: String {
        guard let progress = state.experimentProgress else { return "" }
        switch progress.phase {
        case .collecting:
            return "Collecting tracks..."
        case .extractingFeatures:
            return "Extracting features..."
        case .training(let tag, let fold):
            return "Training \(tag) (fold \(fold + 1)/\(state.folds))"
        case .evaluating(let tag):
            return "Evaluating \(tag)..."
        case .complete:
            return "Complete"
        }
    }
}

#Preview {
    ExperimentContentView()
        .environment(ModelLabState())
        .frame(width: 800, height: 600)
}
