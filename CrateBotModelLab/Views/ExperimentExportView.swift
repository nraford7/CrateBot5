import SwiftUI
import AppKit
import CrateBotCore

struct ExperimentExportView: View {
    @Environment(ModelLabState.self) private var state
    @State private var exportFormat: ExportFormat = .json

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"
        case markdown = "Markdown Report"
    }

    var body: some View {
        if let result = state.currentExperiment {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupBox("Export Configuration") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Export the optimal configuration from your experiment for use in CrateBot.")

                            GroupBox("Recommended Configuration") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Extractors:")
                                        Spacer()
                                        Text(result.configuration.extractors.joined(separator: ", "))
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack {
                                        Text("Viable Tags:")
                                        Spacer()
                                        Text("\(result.viableTags.count)")
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack {
                                        Text("Expected Accuracy:")
                                        Spacer()
                                        Text("\(Int(result.averageAccuracy * 100))%")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }

                            GroupBox("Optimal Thresholds") {
                                ForEach(result.viableTags) { tag in
                                    HStack {
                                        Text(tag.tag)
                                        Spacer()
                                        Text(String(format: "%.2f", tag.optimalThreshold))
                                            .font(.system(.body, design: .monospaced))
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    GroupBox("Export Options") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Format", selection: $exportFormat) {
                                ForEach(ExportFormat.allCases, id: \.self) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                Button {
                                    exportConfig()
                                } label: {
                                    Label("Export Configuration", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    copyToClipboard()
                                } label: {
                                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    GroupBox("Preview") {
                        ScrollView(.horizontal) {
                            Text(generateExport())
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(height: 200)
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Results to Export",
                systemImage: "square.and.arrow.up",
                description: Text("Run an experiment first")
            )
        }
    }

    private func generateExport() -> String {
        guard let result = state.currentExperiment else { return "" }

        switch exportFormat {
        case .json:
            return generateJSON(result)
        case .csv:
            return generateCSV(result)
        case .markdown:
            return generateMarkdown(result)
        }
    }

    private func generateJSON(_ result: ExperimentResult) -> String {
        let config: [String: Any] = [
            "name": result.configuration.name,
            "extractors": result.configuration.extractors,
            "viable_tags": result.viableTags.map { tag in
                [
                    "tag": tag.tag,
                    "threshold": tag.optimalThreshold,
                    "f1_score": tag.metrics.f1Score
                ] as [String: Any]
            },
            "average_accuracy": result.averageAccuracy
        ]

        if let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }

    private func generateCSV(_ result: ExperimentResult) -> String {
        var csv = "tag,accuracy,precision,recall,f1,threshold,positive_count,negative_count,viable\n"
        for tag in result.tagResults {
            csv += "\(tag.tag),\(tag.metrics.accuracy),\(tag.metrics.precision),\(tag.metrics.recall),\(tag.metrics.f1Score),\(tag.optimalThreshold),\(tag.positiveCount),\(tag.negativeCount),\(tag.isViable)\n"
        }
        return csv
    }

    private func generateMarkdown(_ result: ExperimentResult) -> String {
        """
        # Model Lab Experiment Report

        **Name:** \(result.configuration.name)
        **Date:** \(result.completedAt.formatted())
        **Sample Size:** \(result.configuration.sampleSize.rawValue)
        **Tracks Used:** \(result.tracksUsed)
        **Duration:** \(Int(result.duration))s

        ## Summary

        - Average Accuracy: \(Int(result.averageAccuracy * 100))%
        - Average F1 Score: \(String(format: "%.2f", result.averageF1))
        - Viable Tags: \(result.viableTags.count)/\(result.tagResults.count)

        ## Per-Tag Results

        | Tag | Accuracy | F1 | Threshold | Viable |
        |-----|----------|----|-----------| -------|
        \(result.tagResults.map { "| \($0.tag) | \(Int($0.metrics.accuracy * 100))% | \(String(format: "%.2f", $0.metrics.f1Score)) | \(String(format: "%.2f", $0.optimalThreshold)) | \($0.isViable ? "Yes" : "No") |" }.joined(separator: "\n"))
        """
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText, .plainText]
        panel.nameFieldStringValue = "experiment-config"

        if panel.runModal() == .OK, let url = panel.url {
            let content = generateExport()
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func copyToClipboard() {
        let content = generateExport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}
