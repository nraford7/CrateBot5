import SwiftUI
import SwiftData
import CrateBotCore
import os.log

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
            // Log the error
            Logger(subsystem: "com.cratebot", category: "App")
                .error("ModelContainer creation failed: \(error.localizedDescription). Attempting recovery...")

            // Try to recover by deleting corrupted database
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                Logger(subsystem: "com.cratebot", category: "App")
                    .error("Cannot access Application Support directory, using in-memory storage")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [memoryConfig])
                } catch {
                    fatalError("Cannot create even in-memory ModelContainer: \(error)")
                }
            }
            let dbPath = appSupport.appendingPathComponent("default.store")

            do {
                if FileManager.default.fileExists(atPath: dbPath.path) {
                    try FileManager.default.removeItem(at: dbPath)
                    Logger(subsystem: "com.cratebot", category: "App")
                        .info("Removed corrupted database, retrying...")
                }
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                // Last resort: use in-memory storage
                Logger(subsystem: "com.cratebot", category: "App")
                    .error("Recovery failed, using in-memory storage: \(error.localizedDescription)")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [memoryConfig])
                } catch {
                    // This should never happen with in-memory, but handle it
                    fatalError("Cannot create even in-memory ModelContainer: \(error)")
                }
            }
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
