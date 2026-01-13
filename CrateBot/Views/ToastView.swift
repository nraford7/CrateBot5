import SwiftUI
import CrateBotCore

struct ToastView: View {
    let toast: AppState.Toast
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(toast.kind == .success ? .green : .red)

            Text(toast.message)
                .font(.callout)

            Spacer()

            Button {
                appState.dismissToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, 20)
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

#Preview {
    ToastView(toast: .init(message: "Files tagged successfully", kind: .success))
        .environment(AppState())
}
