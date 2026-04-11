import SwiftUI
import CrateBotCore

struct AddFallbackMappingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var userTag: String = ""
    @State private var selectedSource: TagFallbackMapping.EssentiaSource = .mood
    @State private var selectedLabel: String = ""
    @State private var searchText: String = ""

    private var availableLabels: [String] {
        let labels = selectedSource.availableLabels
        if searchText.isEmpty {
            return labels
        }
        return labels.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var canSave: Bool {
        !userTag.trimmingCharacters(in: .whitespaces).isEmpty && !selectedLabel.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        TextField("Your Tag Name", text: $userTag)
                            .textFieldStyle(.roundedBorder)
                    } header: {
                        Text("Your Tag")
                    } footer: {
                        Text("The tag name you want to use (e.g., \"chill\", \"dark\")")
                    }

                    Section {
                        Picker("Source", selection: $selectedSource) {
                            ForEach(TagFallbackMapping.EssentiaSource.allCases, id: \.self) { source in
                                Text(source.displayName).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedSource) { _, _ in
                            selectedLabel = ""
                            searchText = ""
                        }
                    } header: {
                        Text("Essentia Source")
                    }

                    Section {
                        TextField("Search labels...", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(availableLabels, id: \.self) { label in
                                    Button {
                                        selectedLabel = label
                                    } label: {
                                        HStack {
                                            Text(label)
                                                .font(Theme.Fonts.body(13))
                                                .foregroundColor(selectedLabel == label ? Theme.Colors.accentPrimary : Theme.Colors.textPrimary)

                                            Spacer()

                                            if selectedLabel == label {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(Theme.Colors.accentPrimary)
                                                    .font(.system(size: 12, weight: .semibold))
                                            }
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                        .background(selectedLabel == label ? Theme.Colors.accentPrimary.opacity(0.1) : Color.clear)
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 200)
                    } header: {
                        HStack {
                            Text("Essentia Label")
                            Spacer()
                            if !selectedLabel.isEmpty {
                                Text("Selected: \(selectedLabel)")
                                    .font(Theme.Fonts.mono(11))
                                    .foregroundColor(Theme.Colors.accentPrimary)
                            }
                        }
                    } footer: {
                        Text("\(selectedSource.availableLabels.count) labels available")
                    }
                }
                .formStyle(.grouped)
            }
            .background(Theme.Colors.bgWindow)
            .navigationTitle("Add Fallback Mapping")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addMapping()
                    }
                    .disabled(!canSave)
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .frame(width: 450, height: 550)
    }

    private func addMapping() {
        let mapping = TagFallbackMapping(
            userTag: userTag.trimmingCharacters(in: .whitespaces),
            essentiaSource: selectedSource,
            essentiaLabel: selectedLabel
        )
        appState.fallbackMappingConfig.setMapping(mapping)
        dismiss()
    }
}

#Preview {
    AddFallbackMappingSheet()
        .environment(AppState())
}
