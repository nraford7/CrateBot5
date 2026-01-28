import SwiftUI
import CrateBotCore

struct ExperimentSetupView: View {
    @Environment(ModelLabState.self) private var state
    @State private var experimentName = "Experiment 1"
    @State private var showFolderPicker = false
    @State private var isScanning = false

    var body: some View {
        @Bindable var state = state

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: Folders
                GroupBox("Music Folders") {
                    VStack(alignment: .leading, spacing: 12) {
                        if state.selectedFolders.isEmpty {
                            Text("No folders selected")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(state.selectedFolders, id: \.self) { url in
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue)
                                    Text(url.lastPathComponent)
                                    Spacer()
                                    Button {
                                        state.removeFolder(url)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button {
                            showFolderPicker = true
                        } label: {
                            Label("Add Folder", systemImage: "plus")
                        }
                        .fileImporter(
                            isPresented: $showFolderPicker,
                            allowedContentTypes: [.folder]
                        ) { result in
                            if case .success(let url) = result {
                                state.addFolder(url)
                            }
                        }

                        if !state.selectedFolders.isEmpty {
                            Button {
                                Task { await scanForTags() }
                            } label: {
                                if isScanning {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Label("Scan Tags", systemImage: "tag")
                                }
                            }
                            .disabled(isScanning)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Section 2: Sample Size
                GroupBox("Sample Size") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Size", selection: $state.sampleSize) {
                            ForEach(SampleSize.allCases, id: \.self) { size in
                                Text("\(size.rawValue) \(size.estimatedTime)")
                                    .tag(size)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Text("Stratified sampling preserves tag distribution")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // Section 3: Feature Extractors
                GroupBox("Feature Extractors") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ModelLabState.availableExtractors, id: \.id) { extractor in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { state.selectedExtractors.contains(extractor.id) },
                                    set: { isOn in
                                        if isOn {
                                            state.selectedExtractors.insert(extractor.id)
                                        } else {
                                            state.selectedExtractors.remove(extractor.id)
                                        }
                                    }
                                )) {
                                    Text(extractor.name)
                                }
                                .disabled(!extractor.available)

                                if !extractor.available {
                                    Text("Coming soon")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Section 4: Tags to Test
                if !state.allTags.isEmpty {
                    GroupBox("Tags to Test (\(state.experimentTags.count) selected)") {
                        VStack(alignment: .leading, spacing: 8) {
                            let sortedTags = state.allTags.sorted { $0.value > $1.value }

                            ForEach(sortedTags, id: \.key) { tag, count in
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { state.experimentTags.contains(tag) },
                                        set: { isOn in
                                            if isOn {
                                                state.experimentTags.insert(tag)
                                            } else {
                                                state.experimentTags.remove(tag)
                                            }
                                        }
                                    )) {
                                        Text(tag)
                                    }

                                    Spacer()

                                    Text("\(count) tracks")
                                        .font(.caption)
                                        .foregroundStyle(count >= 50 ? .green : .orange)
                                }
                            }

                            HStack {
                                Button("Select All Viable") {
                                    state.experimentTags = Set(state.allTags.filter { $0.value >= 50 }.keys)
                                }
                                Button("Clear") {
                                    state.experimentTags.removeAll()
                                }
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Section 5: Run
                GroupBox("Experiment") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name", text: $experimentName)
                            .textFieldStyle(.roundedBorder)

                        Stepper("Folds: \(state.folds)", value: $state.folds, in: 2...10)

                        HStack {
                            Button {
                                Task { await runExperiment() }
                            } label: {
                                Label("Run Experiment", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canRun)

                            if state.isExperimentRunning {
                                Button("Cancel") {
                                    state.resetExperiment()
                                }
                            }
                        }

                        if !canRun {
                            Text(cannotRunReason)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding()
        }
    }

    private var canRun: Bool {
        !state.selectedFolders.isEmpty &&
        !state.selectedExtractors.isEmpty &&
        !state.experimentTags.isEmpty &&
        !state.isExperimentRunning
    }

    private var cannotRunReason: String {
        if state.selectedFolders.isEmpty { return "Add at least one folder" }
        if state.selectedExtractors.isEmpty { return "Select at least one extractor" }
        if state.experimentTags.isEmpty { return "Select at least one tag" }
        if state.isExperimentRunning { return "Experiment in progress" }
        return ""
    }

    private func scanForTags() async {
        isScanning = true
        defer { isScanning = false }

        let collector = TrainingDataCollector()
        let result = await collector.collectTrainingData(from: state.selectedFolders)
        let tagCounts = await collector.discoverTags(from: result.tracks)

        await MainActor.run {
            state.allTags = tagCounts
            state.experimentTags = Set(tagCounts.filter { $0.value >= 50 }.keys)
        }
    }

    private func runExperiment() async {
        state.isExperimentRunning = true
        defer { state.isExperimentRunning = false }

        let config = ExperimentConfiguration(
            name: experimentName,
            sampleSize: state.sampleSize,
            extractors: Array(state.selectedExtractors),
            folds: state.folds,
            tags: Array(state.experimentTags)
        )

        let runner = ExperimentRunner()

        do {
            let result = try await runner.runExperiment(
                directories: state.selectedFolders,
                configuration: config
            ) { progress in
                await MainActor.run {
                    state.experimentProgress = progress
                }
            }

            await MainActor.run {
                state.currentExperiment = result
                state.experimentHistory.insert(result, at: 0)
            }
        } catch {
            await MainActor.run {
                state.errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ExperimentSetupView()
        .environment(ModelLabState())
        .frame(width: 600, height: 800)
}
