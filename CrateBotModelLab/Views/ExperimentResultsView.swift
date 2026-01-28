import SwiftUI
import Charts
import CrateBotCore

struct ExperimentResultsView: View {
    @Environment(ModelLabState.self) private var state

    var body: some View {
        if let result = state.currentExperiment {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summarySection(result)
                    accuracyChart(result)
                    tagResultsSection(result)
                    viabilitySection(result)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Results",
                systemImage: "chart.bar",
                description: Text("Run an experiment to see results")
            )
        }
    }

    @ViewBuilder
    private func summarySection(_ result: ExperimentResult) -> some View {
        GroupBox("Summary") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(title: "Avg Accuracy", value: "\(Int(result.averageAccuracy * 100))%", color: .blue)
                StatCard(title: "Avg F1 Score", value: String(format: "%.2f", result.averageF1), color: .green)
                StatCard(title: "Tags Tested", value: "\(result.tagResults.count)", color: .purple)
                StatCard(title: "Tracks Used", value: "\(result.tracksUsed)", color: .orange)
            }

            HStack {
                Text("Duration: \(Int(result.duration))s")
                Spacer()
                Text("Sample: \(result.configuration.sampleSize.rawValue)")
                Spacer()
                Text("Folds: \(result.configuration.folds)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func accuracyChart(_ result: ExperimentResult) -> some View {
        GroupBox("Accuracy by Tag") {
            Chart(result.tagResults) { tagResult in
                BarMark(
                    x: .value("Tag", tagResult.tag),
                    y: .value("Accuracy", tagResult.metrics.accuracy)
                )
                .foregroundStyle(tagResult.isViable ? .green : .orange)
                .annotation(position: .top) {
                    Text("\(Int(tagResult.metrics.accuracy * 100))%")
                        .font(.caption2)
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v * 100))%")
                        }
                    }
                }
            }
            .frame(height: 250)
            .padding()
        }
    }

    @ViewBuilder
    private func tagResultsSection(_ result: ExperimentResult) -> some View {
        GroupBox("Per-Tag Results") {
            Table(result.tagResults) {
                TableColumn("Tag") { tagResult in
                    HStack {
                        Circle()
                            .fill(tagResult.isViable ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(tagResult.tag)
                    }
                }
                TableColumn("Accuracy") { tagResult in
                    Text("\(Int(tagResult.metrics.accuracy * 100))%")
                }
                TableColumn("Precision") { tagResult in
                    Text(String(format: "%.2f", tagResult.metrics.precision))
                }
                TableColumn("Recall") { tagResult in
                    Text(String(format: "%.2f", tagResult.metrics.recall))
                }
                TableColumn("F1") { tagResult in
                    Text(String(format: "%.2f", tagResult.metrics.f1Score))
                }
                TableColumn("Threshold") { tagResult in
                    Text(String(format: "%.2f", tagResult.optimalThreshold))
                }
                TableColumn("Samples") { tagResult in
                    Text("\(tagResult.positiveCount)+/\(tagResult.negativeCount)-")
                        .font(.caption)
                }
            }
            .frame(minHeight: 300)
        }
    }

    @ViewBuilder
    private func viabilitySection(_ result: ExperimentResult) -> some View {
        GroupBox("Tag Viability") {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Viable Tags (\(result.viableTags.count))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    ForEach(result.viableTags) { tag in
                        Text("• \(tag.tag) (F1: \(String(format: "%.2f", tag.metrics.f1Score)))")
                            .font(.caption)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Non-Viable Tags (\(result.nonViableTags.count))", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    ForEach(result.nonViableTags) { tag in
                        HStack {
                            Text("• \(tag.tag)")
                            if tag.positiveCount < 50 {
                                Text("(only \(tag.positiveCount) samples)")
                            } else {
                                Text("(F1: \(String(format: "%.2f", tag.metrics.f1Score)))")
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
struct ExperimentResultsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = ModelLabState()
        state.currentExperiment = ExperimentResult(
            configuration: ExperimentConfiguration(
                name: "Test",
                sampleSize: .balanced,
                extractors: ["spectral"],
                folds: 5,
                tags: ["House", "Techno", "Disco"]
            ),
            tagResults: [
                TagExperimentResult(
                    tag: "House",
                    metrics: ValidationMetrics(
                        accuracy: 0.85, precision: 0.82, recall: 0.88, f1Score: 0.85,
                        truePositives: 44, falsePositives: 10, trueNegatives: 41, falseNegatives: 6
                    ),
                    optimalThreshold: 0.45,
                    sampleCount: 101,
                    positiveCount: 50,
                    negativeCount: 51
                ),
                TagExperimentResult(
                    tag: "Techno",
                    metrics: ValidationMetrics(
                        accuracy: 0.78, precision: 0.75, recall: 0.80, f1Score: 0.77,
                        truePositives: 40, falsePositives: 13, trueNegatives: 38, falseNegatives: 10
                    ),
                    optimalThreshold: 0.50,
                    sampleCount: 101,
                    positiveCount: 50,
                    negativeCount: 51
                ),
                TagExperimentResult(
                    tag: "Disco",
                    metrics: ValidationMetrics(
                        accuracy: 0.55, precision: 0.50, recall: 0.60, f1Score: 0.55,
                        truePositives: 12, falsePositives: 12, trueNegatives: 43, falseNegatives: 8
                    ),
                    optimalThreshold: 0.50,
                    sampleCount: 75,
                    positiveCount: 20,
                    negativeCount: 55
                )
            ],
            duration: 45.0,
            tracksUsed: 100
        )

        return ExperimentResultsView()
            .environment(state)
            .frame(width: 900, height: 800)
    }
}
#endif
