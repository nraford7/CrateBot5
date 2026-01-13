import SwiftUI
import CrateBotCore

struct ModelLabContentView: View {
    @Environment(ModelLabState.self) private var labState
    @State private var showTagSelection = false
    @State private var trainingTask: Task<Void, Never>?

    var body: some View {
        @Bindable var bindableState = labState

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Lab")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Train custom tagging models from your organized music collection.")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)

                // Training Directory
                TrainingDirectoryCard()

                // Model Name
                ModelNameCard(labState: bindableState)

                // Actions
                if labState.trainingStatus == .idle {
                    idleActions
                } else if labState.trainingStatus == .running || labState.trainingStatus == .paused {
                    TrainingProgressView()
                } else {
                    completedView
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
        .sheet(isPresented: $showTagSelection) {
            TagSelectionSheet()
        }
        .onChange(of: labState.trainingStatus) { oldValue, newValue in
            if newValue == .running && oldValue != .running {
                startTraining()
            } else if newValue == .cancelled {
                trainingTask?.cancel()
                trainingTask = nil
            }
        }
    }

    private func startTraining() {
        guard let directory = labState.trainingDirectory,
              let selectedTags = labState.selectedTags else {
            labState.trainingStatus = .failed
            labState.addLog("No directory or tags selected", level: .error)
            return
        }

        // Combine all selected tags
        let allTags = selectedTags.genre + selectedTags.timing + selectedTags.mood + selectedTags.descriptive
        guard !allTags.isEmpty else {
            labState.trainingStatus = .failed
            labState.addLog("No tags selected for training", level: .error)
            return
        }

        labState.addLog("Starting training with \(allTags.count) tags")
        labState.trainingPhase = "Initializing..."

        trainingTask = Task {
            do {
                let runner = ExperimentRunner()
                let config = ExperimentConfiguration(
                    name: labState.modelName,
                    sampleSize: labState.sampleSize,
                    extractors: Array(labState.selectedExtractors),
                    folds: labState.folds,
                    tags: allTags
                )

                let result = try await runner.runExperiment(
                    directories: [directory],
                    configuration: config
                ) { progress in
                    await MainActor.run {
                        updateProgress(progress)
                    }
                }

                await MainActor.run {
                    labState.currentExperiment = result
                    labState.experimentHistory.insert(result, at: 0)
                    labState.trainingStatus = .completed
                    labState.trainingProgress = 1.0
                    labState.trainingPhase = "Complete"
                    labState.addLog("Training complete! Average accuracy: \(Int(result.averageAccuracy * 100))%")
                }
            } catch {
                await MainActor.run {
                    if Task.isCancelled {
                        labState.trainingStatus = .cancelled
                        labState.addLog("Training cancelled", level: .warning)
                    } else {
                        labState.trainingStatus = .failed
                        labState.addLog("Training failed: \(error.localizedDescription)", level: .error)
                    }
                }
            }
        }
    }

    private func updateProgress(_ progress: ExperimentProgress) {
        labState.trainingProgress = progress.overallProgress

        switch progress.phase {
        case .collecting:
            labState.trainingPhase = "Collecting tracks..."
        case .extractingFeatures:
            labState.trainingPhase = "Extracting audio features..."
        case .training(let tag, let fold):
            labState.trainingPhase = "Training \(tag) (fold \(fold + 1)/\(labState.folds))"
            labState.currentFile = tag
        case .evaluating(let tag):
            labState.trainingPhase = "Evaluating \(tag)..."
        case .complete:
            labState.trainingPhase = "Complete"
        }

        if progress.totalTags > 0 {
            labState.filesProcessed = progress.tagsCompleted
            labState.totalFiles = progress.totalTags
        }
    }

    private var idleActions: some View {
        HStack {
            Button {
                showTagSelection = true
            } label: {
                Label("Scan & Select Tags", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(labState.trainingDirectory == nil)
        }
        .padding(.horizontal)
    }

    private var completedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrainingProgressView()

            HStack {
                Button {
                    labState.reset()
                } label: {
                    Label("Train Another", systemImage: "arrow.clockwise")
                }

                if labState.trainingStatus == .completed {
                    Button {
                        // Load the trained model
                    } label: {
                        Label("Load Model", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    ModelLabContentView()
        .environment(ModelLabState())
}
