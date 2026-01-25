import SwiftUI
import CrateBotCore

struct MainHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            Spacer()
            // Tab switcher centered in the window
            HStack(spacing: 2) {
                ForEach(AppState.AppView.allCases, id: \.self) { view in
                    TabButton(
                        title: view.displayName,
                        isSelected: appState.currentView == view
                    ) {
                        withAnimation(Theme.Animation.smooth) {
                            appState.currentView = view
                        }
                    }
                }
            }
            .padding(3)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.sm)
            Spacer()
        }
        // Logo as overlay so it doesn't affect centering
        .overlay(alignment: .leading) {
            CrateBotLogo(isProcessing: appState.isTagging || appState.isLoadingModel)
                .padding(.leading, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.bgElevated)
        .overlay(alignment: .bottom) {
            // Subtle bottom border with gradient
            LinearGradient(
                colors: [Theme.Colors.accentPrimary.opacity(0.3), Theme.Colors.accentSecondary.opacity(0.1), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.label(12))
                .foregroundColor(isSelected ? Theme.Colors.bgBase : (isHovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs + 2)
                .background(
                    isSelected
                        ? Theme.Colors.accentPrimary
                        : (isHovered ? Theme.Colors.bgHover : .clear)
                )
                .cornerRadius(Theme.Radius.xs)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    MainHeader()
        .environment(AppState())
}
