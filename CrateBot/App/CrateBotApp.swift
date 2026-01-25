import SwiftUI
import SwiftData
import CrateBotCore

@main
struct CrateBotApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([CachedFeatures.self, TagOverride.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
                .task {
                    // Restore security-scoped bookmarks for music folders
                    _ = appState.bookmarkManager.restoreAllAccess()

                    // Load default/last-used model on app startup
                    await appState.loadDefaultModel()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
