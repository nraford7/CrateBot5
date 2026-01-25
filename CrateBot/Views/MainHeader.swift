import SwiftUI
import CrateBotCore

struct MainHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // App title
            Text("CrateBot")
                .font(Theme.Fonts.heading(20))
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            // Tab switcher (centered)
            Picker("", selection: Binding(
                get: { appState.currentView },
                set: { appState.currentView = $0 }
            )) {
                ForEach(AppState.AppView.allCases, id: \.self) { view in
                    Text(view.displayName).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            Spacer()

            // Settings button
            Button {
                appState.settingsOpen = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.bgSurface)
            .cornerRadius(Theme.Radius.sm)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.bgElevated)
    }
}

#Preview {
    MainHeader()
        .environment(AppState())
}
