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
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        ))
                case .train:
                    TrainView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        ))
                case .refine:
                    RefineView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        ))
                }
            }
            .animation(Theme.Animation.smooth, value: appState.currentView)

            StatusBar()
        }
        .background(Theme.Colors.bgBase)
        .overlay(NoiseOverlay(opacity: 0.02))
        .sheet(isPresented: $state.settingsOpen) {
            SettingsPanel()
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Animation.bounce, value: appState.toast != nil)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
