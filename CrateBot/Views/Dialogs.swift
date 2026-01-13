import SwiftUI
import CrateBotCore

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
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)

            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit {
                    submitIfValid()
                }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)

                Button("Submit") {
                    submitIfValid()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 300)
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
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)

            VStack(spacing: 8) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let onCancel = onCancel {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(minWidth: 300)
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
    .confirmDestructiveAction(
        "Clear Queue",
        message: "This will remove all files from the queue.",
        isPresented: $showConfirm
    ) {
        print("Queue cleared!")
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
        print("Renamed to: \(newName)")
    }
}

#Preview("Input Dialog - Empty") {
    @Previewable @State var newName = ""

    InputDialog(
        title: "Create Playlist",
        prompt: "Enter playlist name",
        text: $newName
    ) { name in
        print("Created: \(name)")
    }
}

#Preview("Progress Dialog") {
    ProgressDialog(
        title: "Importing",
        progress: 0.35,
        status: "Processing file 3 of 10..."
    ) {
        print("Cancelled!")
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
