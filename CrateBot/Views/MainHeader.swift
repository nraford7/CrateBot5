import SwiftUI
import CrateBotCore

struct MainHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            // App title
            Text("CrateBot")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            // View switcher
            Picker("View", selection: Binding(
                get: { appState.currentView },
                set: { appState.currentView = $0 }
            )) {
                ForEach(AppState.AppView.allCases, id: \.self) { view in
                    Text(view.rawValue.capitalized).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            Spacer()

            // Settings button
            Button {
                appState.settingsOpen = true
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

#Preview {
    MainHeader()
        .environment(AppState())
}
