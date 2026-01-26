import SwiftUI
import CrateBotCore

/// Full-screen editor for fallback mappings showing all model tags
struct FallbackMappingsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var selectedTag: String?
    @State private var searchText: String = ""

    private let fallbackManager = FallbackMappingManager()

    /// Get effective mappings based on mode (default vs custom)
    private var effectiveMappings: [TagFallbackMapping] {
        if appState.fallbackMappingConfig.useDefaultMappings {
            return fallbackManager.generateDefaultMappings(for: appState.loadedTagNames)
        } else {
            return appState.fallbackMappingConfig.mappings
        }
    }

    /// Get mapping for a tag from effective mappings
    private func effectiveMapping(for tag: String) -> TagFallbackMapping? {
        effectiveMappings.first { $0.userTag.lowercased() == tag.lowercased() }
    }

    // MARK: - Tag Grouping

    /// Ordered genre categories for Essentia genres
    private static let genreOrder = [
        "Electronic",
        "Hip Hop",
        "Funk / Soul",
        "Latin",
        "Reggae",
        "Rock"
    ]

    /// Group Essentia genre labels by main genre
    private func groupedGenreLabels(labels: [String]) -> [(genre: String, subgenres: [(full: String, display: String)])] {
        // Parse labels into groups
        var groups: [String: [(full: String, display: String)]] = [:]

        for label in labels {
            if let separatorRange = label.range(of: "---") {
                let mainGenre = String(label[..<separatorRange.lowerBound])
                let subgenre = String(label[separatorRange.upperBound...])
                groups[mainGenre, default: []].append((full: label, display: subgenre))
            } else {
                // No separator - use as-is
                groups["Other", default: []].append((full: label, display: label))
            }
        }

        // Build ordered result
        var result: [(genre: String, subgenres: [(full: String, display: String)])] = []

        // Add in specified order first
        for genre in Self.genreOrder {
            if let subgenres = groups.removeValue(forKey: genre) {
                result.append((genre: genre, subgenres: subgenres.sorted { $0.display < $1.display }))
            }
        }

        // Add remaining genres alphabetically
        for genre in groups.keys.sorted() {
            if let subgenres = groups[genre] {
                result.append((genre: genre, subgenres: subgenres.sorted { $0.display < $1.display }))
            }
        }

        return result
    }

    /// Group user tags by their category using the training tag selections
    private var groupedUserTags: [(category: String, tags: [String])] {
        var genreTags: [String] = []
        var timingTags: [String] = []
        var moodTags: [String] = []
        var otherTags: [String] = []

        // Load the training tag selections which define categories
        let trainingTags = SelectedTrainingTags.load()

        // Create lowercase sets for case-insensitive matching
        let genreSet = Set(trainingTags.genre.map { $0.lowercased() })
        let timingSet = Set(trainingTags.timing.map { $0.lowercased() })
        let moodSet = Set(trainingTags.mood.map { $0.lowercased() })

        for tag in appState.loadedTagNames {
            let normalizedTag = tag.lowercased()
            if genreSet.contains(normalizedTag) {
                genreTags.append(tag)
            } else if timingSet.contains(normalizedTag) {
                timingTags.append(tag)
            } else if moodSet.contains(normalizedTag) {
                moodTags.append(tag)
            } else {
                // Descriptive category or unrecognized tags go to "Descriptive"
                otherTags.append(tag)
            }
        }

        var result: [(category: String, tags: [String])] = []
        if !genreTags.isEmpty { result.append(("Genre", genreTags)) }
        if !timingTags.isEmpty { result.append(("Timing", timingTags)) }
        if !moodTags.isEmpty { result.append(("Mood", moodTags)) }
        if !otherTags.isEmpty { result.append(("Descriptive", otherTags)) }

        return result
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            HSplitView {
                // Left panel: Tag list
                tagListPanel
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

                // Right panel: Mapping editor
                if let tag = selectedTag {
                    mappingEditorPanel(for: tag)
                        .frame(minWidth: 350)
                } else {
                    emptyStatePanel
                        .frame(minWidth: 350)
                }
            }
            .background(Theme.Colors.bgWindow)
            .navigationTitle("Fallback Mappings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .frame(minWidth: 650, minHeight: 500)
    }

    // MARK: - Tag List Panel

    private var tagListPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Model Tags")
                    .font(Theme.Fonts.heading(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("\(appState.loadedTagNames.count)")
                    .font(Theme.Fonts.mono(12))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)

            Divider()

            // Tag list
            if appState.loadedTagNames.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("No model loaded")
                        .font(Theme.Fonts.body(14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Load a model to configure fallback mappings")
                        .font(Theme.Fonts.body(12))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedUserTags, id: \.category) { group in
                            Section {
                                ForEach(group.tags, id: \.self) { tag in
                                    tagRow(tag)
                                }
                            } header: {
                                HStack {
                                    Text(group.category)
                                        .font(Theme.Fonts.mono(10))
                                        .foregroundColor(Theme.Colors.textTertiary)
                                        .textCase(.uppercase)
                                    Spacer()
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.Colors.bgSurface)
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.Colors.bgSurface)
    }

    private func tagRow(_ tag: String) -> some View {
        let mapping = effectiveMapping(for: tag)
        let hasMapping = mapping != nil && !mapping!.essentiaLabels.isEmpty
        let isSelected = selectedTag == tag

        return Button {
            selectedTag = tag
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                // Tag name
                Text(tag.replacingOccurrences(of: "_", with: " "))
                    .font(Theme.Fonts.body(13))
                    .foregroundColor(isSelected ? Theme.Colors.accentPrimary : Theme.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Mapping indicator
                if hasMapping {
                    Text("\(mapping!.essentiaLabels.count)")
                        .font(Theme.Fonts.mono(10))
                        .foregroundColor(Theme.Colors.accentPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.accentPrimary.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Theme.Colors.accentPrimary.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mapping Editor Panel

    /// Switch from default to custom mode, copying all default mappings
    private func switchToCustomMode() {
        guard appState.fallbackMappingConfig.useDefaultMappings else { return }

        // Copy default mappings to custom
        let defaultMappings = fallbackManager.generateDefaultMappings(for: appState.loadedTagNames)
        appState.fallbackMappingConfig.mappings = defaultMappings
        appState.fallbackMappingConfig.useDefaultMappings = false
    }

    private func mappingEditorPanel(for tag: String) -> some View {
        @Bindable var appState = appState

        let binding = Binding<TagFallbackMapping>(
            get: {
                // Use effective mapping (default or custom)
                effectiveMapping(for: tag) ??
                TagFallbackMapping(userTag: tag, essentiaSource: .mood, essentiaLabels: [])
            },
            set: { newMapping in
                // If in default mode, switch to custom first
                if appState.fallbackMappingConfig.useDefaultMappings {
                    switchToCustomMode()
                }
                appState.fallbackMappingConfig.setMapping(newMapping)
            }
        )

        let isDefaultMode = appState.fallbackMappingConfig.useDefaultMappings

        return VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.replacingOccurrences(of: "_", with: " "))
                        .font(Theme.Fonts.heading(16))
                        .foregroundColor(Theme.Colors.textPrimary)
                    if isDefaultMode {
                        Text("Auto-mapped (edit to customize)")
                            .font(Theme.Fonts.body(11))
                            .foregroundColor(Theme.Colors.accentPrimary)
                    }
                }
                Spacer()

                if !binding.wrappedValue.essentiaLabels.isEmpty {
                    Button {
                        var mapping = binding.wrappedValue
                        mapping.essentiaLabels = []
                        binding.wrappedValue = mapping
                    } label: {
                        Text("Clear All")
                            .font(Theme.Fonts.body(12))
                            .foregroundColor(Theme.Colors.statusError)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Source picker
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Essentia Source")
                            .font(Theme.Fonts.body(12))
                            .foregroundColor(Theme.Colors.textSecondary)

                        Picker("Source", selection: binding.essentiaSource) {
                            ForEach(TagFallbackMapping.EssentiaSource.allCases, id: \.self) { source in
                                Text(source.displayName).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Selected labels
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Text("Selected Labels")
                                .font(Theme.Fonts.body(12))
                                .foregroundColor(Theme.Colors.textSecondary)
                            Spacer()
                            Text("\(binding.wrappedValue.essentiaLabels.count) selected")
                                .font(Theme.Fonts.mono(11))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }

                        if binding.wrappedValue.essentiaLabels.isEmpty {
                            Text("No labels selected")
                                .font(Theme.Fonts.body(13))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.bgElevated)
                                .cornerRadius(Theme.Radius.sm)
                        } else {
                            FlowLayout(spacing: Theme.Spacing.xs) {
                                ForEach(binding.wrappedValue.essentiaLabels, id: \.self) { label in
                                    selectedLabelChip(label, binding: binding)
                                }
                            }
                            .padding(Theme.Spacing.sm)
                            .background(Theme.Colors.bgElevated)
                            .cornerRadius(Theme.Radius.sm)
                        }
                    }

                    // Available labels
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Available Labels")
                            .font(Theme.Fonts.body(12))
                            .foregroundColor(Theme.Colors.textSecondary)

                        TextField("Search labels...", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        availableLabelsGrid(source: binding.wrappedValue.essentiaSource, binding: binding)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .background(Theme.Colors.bgWindow)
    }

    /// Get display name for a label (strips "Genre---" prefix for genres)
    private func displayName(for label: String) -> String {
        if let separatorRange = label.range(of: "---") {
            return String(label[separatorRange.upperBound...])
        }
        return label
    }

    private func selectedLabelChip(_ label: String, binding: Binding<TagFallbackMapping>) -> some View {
        HStack(spacing: 4) {
            Text(displayName(for: label))
                .font(Theme.Fonts.mono(11))
                .foregroundColor(Theme.Colors.textPrimary)

            Button {
                var mapping = binding.wrappedValue
                mapping.essentiaLabels.removeAll { $0 == label }
                binding.wrappedValue = mapping
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.Colors.accentPrimary.opacity(0.15))
        .cornerRadius(4)
    }

    private func availableLabelsGrid(source: TagFallbackMapping.EssentiaSource, binding: Binding<TagFallbackMapping>) -> some View {
        let allLabels = source.availableLabels
        let filteredLabels = searchText.isEmpty ? allLabels : allLabels.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }

        // Use VStack instead of ScrollView to avoid nested scroll issues
        // Parent ScrollView handles scrolling
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Use grouped display for genres only
            if source == .genre {
                let grouped = groupedGenreLabels(labels: filteredLabels)
                ForEach(grouped, id: \.genre) { group in
                    // Section header
                    Text(group.genre)
                        .font(Theme.Fonts.mono(10))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.top, Theme.Spacing.xs)

                    // Subgenres grid - use regular VGrid, not Lazy
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: Theme.Spacing.xs),
                        GridItem(.flexible(), spacing: Theme.Spacing.xs)
                    ], spacing: Theme.Spacing.xs) {
                        ForEach(group.subgenres, id: \.full) { subgenre in
                            labelToggleButton(
                                fullLabel: subgenre.full,
                                displayLabel: subgenre.display,
                                binding: binding
                            )
                        }
                    }
                }
            } else {
                // Flat grid for mood/instrument
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.xs),
                    GridItem(.flexible(), spacing: Theme.Spacing.xs)
                ], spacing: Theme.Spacing.xs) {
                    ForEach(filteredLabels, id: \.self) { label in
                        labelToggleButton(fullLabel: label, displayLabel: label, binding: binding)
                    }
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.bgSurface)
        .cornerRadius(Theme.Radius.sm)
    }

    private func labelToggleButton(fullLabel: String, displayLabel: String, binding: Binding<TagFallbackMapping>) -> some View {
        let isSelected = binding.wrappedValue.essentiaLabels.contains(fullLabel)

        return Button {
            var mapping = binding.wrappedValue
            if isSelected {
                mapping.essentiaLabels.removeAll { $0 == fullLabel }
            } else {
                mapping.essentiaLabels.append(fullLabel)
            }
            binding.wrappedValue = mapping
        } label: {
            HStack {
                Text(displayLabel)
                    .font(Theme.Fonts.body(12))
                    .foregroundColor(isSelected ? Theme.Colors.accentPrimary : Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentPrimary)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isSelected ? Theme.Colors.accentPrimary.opacity(0.1) : Theme.Colors.bgElevated)
            .cornerRadius(Theme.Radius.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStatePanel: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "arrow.left")
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Select a tag")
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Choose a tag from the list to configure its fallback mapping")
                .font(Theme.Fonts.body(12))
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.bgWindow)
    }
}

// MARK: - Preview

#Preview {
    FallbackMappingsEditor()
        .environment(AppState())
}
