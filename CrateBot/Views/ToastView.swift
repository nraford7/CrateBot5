import SwiftUI
import CrateBotCore

struct ToastView: View {
    let toast: AppState.Toast
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(toast.kind == .success ? Theme.Colors.statusSuccess : Theme.Colors.statusError)

            Text(toast.message)
                .font(Theme.Fonts.body(14))
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            Button {
                appState.dismissToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.bgSurface)
        .cornerRadius(Theme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.Colors.textTertiary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    appState.dismissToast()
                }
            }
        }
    }
}

#Preview("Success") {
    ToastView(toast: .init(message: "Files tagged successfully", kind: .success))
        .environment(AppState())
        .frame(width: 500)
        .background(Theme.Colors.bgWindow)
}

#Preview("Error") {
    ToastView(toast: .init(message: "Failed to process 3 files", kind: .error))
        .environment(AppState())
        .frame(width: 500)
        .background(Theme.Colors.bgWindow)
}
