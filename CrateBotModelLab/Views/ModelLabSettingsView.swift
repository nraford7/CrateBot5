import SwiftUI

struct ModelLabSettingsView: View {
    @AppStorage("defaultFolds") private var defaultFolds = 5
    @AppStorage("defaultSeed") private var defaultSeed = 42

    var body: some View {
        Form {
            Section("Defaults") {
                Stepper("Default Folds: \(defaultFolds)", value: $defaultFolds, in: 2...10)
                TextField("Random Seed", value: $defaultSeed, format: .number)
            }

            Section("About") {
                Text("Model Lab v1.0")
                Text("Part of CrateBot")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
