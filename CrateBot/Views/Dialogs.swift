import SwiftUI
import CrateBotCore
import os.log

private let logger = Logger(subsystem: "com.cratebot", category: "Dialogs")

// MARK: - ConfirmationDialog ViewModifier

/// A reusable modifier for destructive action confirmations.
struct ConfirmDestructiveActionModifier: ViewModifier {
    let title: String
    let message: String
    @Binding var isPresented: Bool
    let confirmAction: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                title,
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button(title, role: .destructive) {
                    confirmAction()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// Presents a confirmation dialog for destructive actions.
    /// - Parameters:
    ///   - title: The title of the confirmation dialog.
    ///   - message: The message explaining the action.
    ///   - isPresented: Binding to control dialog presentation.
    ///   - action: The action to perform when confirmed.
    func confirmDestructiveAction(
        _ title: String,
        message: String,
        isPresented: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        modifier(ConfirmDestructiveActionModifier(
            title: title,
            message: message,
            isPresented: isPresented,
            confirmAction: action
        ))
    }
}

// MARK: - AlertDialog ViewModifier

/// A reusable modifier for error/info alerts.
struct AlertDialogModifier: ViewModifier {
    let title: String
    let message: String
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// Presents an alert dialog for errors or informational messages.
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - message: The message to display.
    ///   - isPresented: Binding to control alert presentation.
    func alertDialog(
        _ title: String,
        message: String,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(AlertDialogModifier(
            title: title,
            message: message,
            isPresented: isPresented
        ))
    }
}

// MARK: - InputDialog View

/// A sheet dialog for text input.
struct InputDialog: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(title)
                .font(Theme.Fonts.heading(18))
                .foregroundColor(Theme.Colors.textPrimary)

            Text(prompt)
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textSecondary)

            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Fonts.body(14))
                .focused($isTextFieldFocused)
                .onSubmit {
                    submitIfValid()
                }

            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Submit") {
                    submitIfValid()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 300)
        .background(Theme.Colors.bgWindow)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    private func submitIfValid() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        onSubmit(trimmedText)
        dismiss()
    }
}

// MARK: - ProgressDialog View

/// A modal dialog showing ongoing progress.
struct ProgressDialog: View {
    let title: String
    let progress: Double
    let status: String
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(title)
                .font(Theme.Fonts.heading(18))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                ThemedProgressBar(progress: progress)

                Text(status)
                    .font(Theme.Fonts.body(12))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            if let onCancel = onCancel {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 300)
        .background(Theme.Colors.bgWindow)
        .interactiveDismissDisabled(onCancel == nil)
    }
}

// MARK: - Previews

#Preview("Confirmation Dialog") {
    @Previewable @State var showConfirm = true

    VStack {
        Text("Tap button to show dialog")
        Button("Clear Queue") {
            showConfirm = true
        }
    }
    .frame(width: 300, height: 200)
    .background(Theme.Colors.bgWindow)
    .confirmDestructiveAction(
        "Clear Queue",
        message: "This will remove all files from the queue.",
        isPresented: $showConfirm
    ) {
        logger.debug("Queue cleared!")
    }
}

#Preview("Alert Dialog") {
    @Previewable @State var showError = true

    VStack {
        Text("Tap button to show alert")
        Button("Show Error") {
            showError = true
        }
    }
    .frame(width: 300, height: 200)
    .background(Theme.Colors.bgWindow)
    .alertDialog(
        "Error",
        message: "Failed to load the model. Please check your configuration.",
        isPresented: $showError
    )
}

#Preview("Input Dialog") {
    @Previewable @State var modelName = "MyModel"

    InputDialog(
        title: "Rename Model",
        prompt: "Enter new name",
        text: $modelName
    ) { newName in
        logger.debug("Renamed to: \(newName)")
    }
}

#Preview("Input Dialog - Empty") {
    @Previewable @State var newName = ""

    InputDialog(
        title: "Create Playlist",
        prompt: "Enter playlist name",
        text: $newName
    ) { name in
        logger.debug("Created: \(name)")
    }
}

#Preview("Progress Dialog") {
    ProgressDialog(
        title: "Importing",
        progress: 0.35,
        status: "Processing file 3 of 10..."
    ) {
        logger.debug("Cancelled!")
    }
}

#Preview("Progress Dialog - No Cancel") {
    ProgressDialog(
        title: "Analyzing",
        progress: 0.7,
        status: "Extracting audio features..."
    )
}

#Preview("Progress Dialog - Complete") {
    ProgressDialog(
        title: "Import Complete",
        progress: 1.0,
        status: "All files processed successfully"
    )
}
