import SwiftUI
import SwiftData
import CrateBotCore

@main
struct ModelLabApp: App {
    @State private var labState = ModelLabState()

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
            ModelLabContentView()
                .environment(labState)
                .modelContainer(sharedModelContainer)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
