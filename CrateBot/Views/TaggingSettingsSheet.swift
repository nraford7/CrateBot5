import SwiftUI
import CrateBotCore

/// Sheet displayed before tagging to configure output settings
struct TaggingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var showFallbackEditor = false

    /// Callback when user confirms and wants to start tagging
    var onStartTagging: () -> Void

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tagging Options")
                    .font(Theme.Fonts.heading(18))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            // Settings content
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    // Mapping card
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Mapping")
                            .font(Theme.Fonts.heading(14))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(.bottom, Theme.Spacing.xs)

                        tagFieldRow(
                            label: "Genre",
                            enabled: $appState.taggingPreferences.genre.enabled,
                            targetField: $appState.taggingPreferences.genre.targetField
                        )

                        tagFieldRow(
                            label: "Sub Genre",
                            enabled: $appState.taggingPreferences.subGenre.enabled,
                            targetField: $appState.taggingPreferences.subGenre.targetField
                        )

                        tagFieldRow(
                            label: "Timing",
                            enabled: $appState.taggingPreferences.album.enabled,
                            targetField: $appState.taggingPreferences.album.targetField
                        )

                        tagFieldRow(
                            label: "Mood",
                            enabled: $appState.taggingPreferences.mood.enabled,
                            targetField: $appState.taggingPreferences.mood.targetField
                        )

                        tagFieldRow(
                            label: "Comments",
                            enabled: $appState.taggingPreferences.comments.enabled,
                            targetField: $appState.taggingPreferences.comments.targetField
                        )

                        tagFieldRow(
                            label: "Likeness",
                            enabled: $appState.taggingPreferences.likeness.enabled,
                            targetField: $appState.taggingPreferences.likeness.targetField
                        )

                        tagFieldRow(
                            label: "Vibes Short",
                            enabled: $appState.taggingPreferences.vibesShort.enabled,
                            targetField: $appState.taggingPreferences.vibesShort.targetField
                        )

                        tagFieldRow(
                            label: "Vibes Long",
                            enabled: $appState.taggingPreferences.vibesLong.enabled,
                            targetField: $appState.taggingPreferences.vibesLong.targetField
                        )

                        let hasAnthropicKey = appState.canUseAnthropicAPI
                        tagFieldRow(
                            label: "AI Descriptions",
                            enabled: aiDescriptionsEnabledBinding,
                            targetField: $appState.taggingPreferences.aiDescriptions.targetField
                        )
                        .disabled(!hasAnthropicKey)
                        .help(hasAnthropicKey
                              ? "Generates short vibe, prose description, and DJ mix-context hint per track via Anthropic API. ~$0.01-$0.02/track at current Sonnet 4 pricing."
                              : "Set the Anthropic API key in Preferences first.")
                        if !hasAnthropicKey {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                Text("Set Anthropic API key in Settings (gear icon) to enable.")
                                    .font(Theme.Fonts.body(11))
                            }
                            .foregroundColor(Theme.Colors.textTertiary)
                            .padding(.leading, Theme.Spacing.lg)
                            .padding(.top, -Theme.Spacing.xs)
                        }

                        tagFieldRow(
                            label: "Hooks",
                            enabled: $appState.taggingPreferences.hooks.enabled,
                            targetField: $appState.taggingPreferences.hooks.targetField
                        )
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.bgSurface)
                    .cornerRadius(Theme.Radius.md)

                    // Fallback Mappings card
                    fallbackMappingsCard

                    // Overwrite option card
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Write Behavior")
                            .font(Theme.Fonts.heading(14))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(.bottom, Theme.Spacing.xs)

                        HStack {
                            Toggle("Overwrite Existing Tags", isOn: $appState.taggingPreferences.overwrite)
                                .font(Theme.Fonts.body(14))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Spacer()
                        }

                        Text("If unchecked, will only write to empty fields")
                            .font(Theme.Fonts.body(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.bgSurface)
                    .cornerRadius(Theme.Radius.md)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.bgWindow)
            .sheet(isPresented: $showFallbackEditor) {
                FallbackMappingsEditor()
                    .environment(appState)
            }

            Divider().background(Theme.Colors.textTertiary.opacity(0.2))

            // Footer with action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button {
                    appState.taggingPreferences.save()
                    dismiss()
                    onStartTagging()
                } label: {
                    Label("Start Tagging", systemImage: "tag")
                }
                .buttonStyle(AccentButtonStyle())
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.bgElevated)
        }
        .frame(width: 500, height: 620)
        .onAppear {
            appState.disableAIDescriptionsIfKeyUnavailable()
        }
    }

    // MARK: - Fallback Mappings Card

    private var fallbackMappingsCard: some View {
        @Bindable var appState = appState

        let effectiveMappings: [TagFallbackMapping] = {
            if appState.fallbackMappingConfig.useDefaultMappings {
                return FallbackMappingManager().generateDefaultMappings(for: appState.loadedTagNames)
            } else {
                return appState.fallbackMappingConfig.mappings
            }
        }()
        let configuredCount = effectiveMappings.filter { !$0.essentiaLabels.isEmpty }.count

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Fallback Mappings")
                .font(Theme.Fonts.heading(14))
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(.bottom, Theme.Spacing.xs)

            HStack {
                Toggle("Enable Fallbacks", isOn: $appState.fallbackMappingConfig.enabled)
                    .font(Theme.Fonts.body(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
            }

            if appState.fallbackMappingConfig.enabled {
                HStack {
                    Toggle("Use Default Mappings", isOn: $appState.fallbackMappingConfig.useDefaultMappings)
                        .font(Theme.Fonts.body(14))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if appState.fallbackMappingConfig.useDefaultMappings {
                            Text("\(configuredCount) tags auto-mapped")
                                .font(Theme.Fonts.body(13))
                                .foregroundColor(Theme.Colors.textSecondary)
                        } else {
                            Text("\(configuredCount) tags configured")
                                .font(Theme.Fonts.body(13))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        showFallbackEditor = true
                    } label: {
                        Label(appState.fallbackMappingConfig.useDefaultMappings ? "View/Edit" : "Edit", systemImage: "pencil")
                            .font(Theme.Fonts.body(12))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(appState.loadedTagNames.isEmpty)
                }

                if appState.loadedTagNames.isEmpty {
                    Text("Load a model to configure mappings")
                        .font(Theme.Fonts.body(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            Text("Boost low-confidence predictions with Essentia")
                .font(Theme.Fonts.body(11))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.bgSurface)
        .cornerRadius(Theme.Radius.md)
    }

    // MARK: - Tag Field Row

    private var aiDescriptionsEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                appState.canUseAnthropicAPI && appState.taggingPreferences.aiDescriptions.enabled
            },
            set: { enabled in
                appState.setAIDescriptionsEnabled(enabled)
            }
        )
    }

    private func tagFieldRow(
        label: String,
        enabled: Binding<Bool>,
        targetField: Binding<String>
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(label, isOn: enabled)
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 120, alignment: .leading)

            Spacer()

            if enabled.wrappedValue {
                Menu {
                    // Standard ID3 fields
                    ForEach(ID3Field.allCases) { field in
                        Button {
                            targetField.wrappedValue = field.frameID
                        } label: {
                            HStack {
                                Text(field.shortName)
                                Spacer()
                                if targetField.wrappedValue == field.frameID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    // Custom TXXX fields
                    Button {
                        targetField.wrappedValue = "TXXX:CRATEBOT_VIBE_SHORT"
                    } label: {
                        HStack {
                            Text("Custom: CRATEBOT_VIBE_SHORT")
                            Spacer()
                            if targetField.wrappedValue == "TXXX:CRATEBOT_VIBE_SHORT" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        targetField.wrappedValue = "TXXX:CRATEBOT_VIBE_LONG"
                    } label: {
                        HStack {
                            Text("Custom: CRATEBOT_VIBE_LONG")
                            Spacer()
                            if targetField.wrappedValue == "TXXX:CRATEBOT_VIBE_LONG" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        targetField.wrappedValue = "TXXX:CRATEBOT_HOOK"
                    } label: {
                        HStack {
                            Text("Custom: CRATEBOT_HOOK")
                            Spacer()
                            if targetField.wrappedValue == "TXXX:CRATEBOT_HOOK" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(ID3Field.displayName(for: targetField.wrappedValue))
                            .font(Theme.Fonts.mono(11))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.bgElevated)
                    .cornerRadius(Theme.Radius.sm)
                }
                .menuStyle(.borderlessButton)
            } else {
                Text("Disabled")
                    .font(Theme.Fonts.mono(11))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Accent Button Style (Blue)

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.body(14))
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Colors.accentPrimary)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
    }
}

// MARK: - Preview

#Preview {
    TaggingSettingsSheet(onStartTagging: {})
        .environment(AppState())
}
