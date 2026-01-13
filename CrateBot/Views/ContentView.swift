import SwiftUI
import CrateBotCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if !appState.setupComplete {
                SetupWizard()
            } else {
                MainView()
            }
        }
    }
}

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            MainHeader()

            ZStack {
                switch appState.currentView {
                case .tagging:
                    TaggingView()
                        .transition(.opacity)
                case .train:
                    TrainView()
                        .transition(.opacity)
                case .refine:
                    RefineView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.currentView)

            StatusBar()
        }
        .sheet(isPresented: $state.settingsOpen) {
            SettingsPanel()
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 60)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
