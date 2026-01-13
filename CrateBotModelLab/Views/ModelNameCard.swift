import SwiftUI

struct ModelNameCard: View {
    @Bindable var labState: ModelLabState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Model Name", systemImage: "doc.text")
                    .font(.headline)

                HStack {
                    TextField("cratebot", text: $labState.modelName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(labState.trainingStatus != .idle)

                    Text(".mlpackage")
                        .foregroundStyle(.secondary)
                }

                Text("Model will be saved to ~/Library/Application Support/CrateBot/Models/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
        .padding(.horizontal)
    }
}

#Preview {
    ModelNameCard(labState: ModelLabState())
}
