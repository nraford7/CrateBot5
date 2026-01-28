import SwiftUI
import SwiftData
import CrateBotCore
import AppKit
import os.log

@main
struct CrateBotApp: App {
    @State private var appState = AppState()

    init() {
        // Set dock icon using SF Symbol
        if let image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "CrateBot") {
            let config = NSImage.SymbolConfiguration(pointSize: 512, weight: .medium)
            let configuredImage = image.withSymbolConfiguration(config) ?? image

            // Create a properly sized image with the symbol centered
            let size = NSSize(width: 512, height: 512)
            let finalImage = NSImage(size: size)
            finalImage.lockFocus()

            // Fill with gradient background
            let gradient = NSGradient(colors: [
                NSColor(red: 0.4, green: 0.3, blue: 0.9, alpha: 1.0),
                NSColor(red: 0.6, green: 0.4, blue: 1.0, alpha: 1.0)
            ])
            gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 135)

            // Draw symbol in white
            let symbolSize = configuredImage.size
            let x = (size.width - symbolSize.width) / 2
            let y = (size.height - symbolSize.height) / 2
            configuredImage.draw(
                in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )

            // Tint the symbol white
            NSColor.white.set()
            NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height).fill(using: .sourceAtop)

            finalImage.unlockFocus()
            NSApplication.shared.applicationIconImage = finalImage
        }
    }

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
