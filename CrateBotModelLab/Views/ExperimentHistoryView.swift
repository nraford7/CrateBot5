import SwiftUI
import CrateBotCore

struct ExperimentHistoryView: View {
    @Environment(ModelLabState.self) private var state

    var body: some View {
        if state.experimentHistory.isEmpty {
            ContentUnavailableView(
                "No History",
                systemImage: "clock",
                description: Text("Run experiments to build history")
            )
        } else {
            Table(state.experimentHistory) {
                TableColumn("Name") { result in
                    Text(result.configuration.name)
                }
                TableColumn("Date") { result in
                    Text(result.completedAt, style: .date)
                }
                TableColumn("Sample") { result in
                    Text(result.configuration.sampleSize.rawValue)
                }
                TableColumn("Tags") { result in
                    Text("\(result.tagResults.count)")
                }
                TableColumn("Avg Accuracy") { result in
                    Text("\(Int(result.averageAccuracy * 100))%")
                }
                TableColumn("Avg F1") { result in
                    Text(String(format: "%.2f", result.averageF1))
                }
                TableColumn("Duration") { result in
                    Text("\(Int(result.duration))s")
                }
            }
        }
    }
}
