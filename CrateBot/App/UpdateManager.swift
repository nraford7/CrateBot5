import Foundation
import SwiftUI
import os.log

// Note: Sparkle import is conditional - when Sparkle is added to the Xcode project,
// uncomment the import and implementation below.

/// Manages app updates via Sparkle
///
/// To enable Sparkle:
/// 1. Add Sparkle SPM dependency to the Xcode project: https://github.com/sparkle-project/Sparkle.git (2.6.0+)
/// 2. Uncomment the Sparkle-specific code below
/// 3. Add SUFeedURL to Info.plist: https://cratebot.app/appcast.xml
@Observable
public final class UpdateManager {
    private let logger = Logger(subsystem: "com.cratebot.app", category: "UpdateManager")

    /// Whether an update is available
    public private(set) var updateAvailable = false

    /// The available update version (if any)
    public private(set) var availableVersion: String?

    /// Whether currently checking for updates
    public private(set) var isChecking = false

    /// Whether currently downloading/installing
    public private(set) var isUpdating = false

    /// Last check date
    public private(set) var lastCheckDate: Date?

    /// Whether automatic checks are enabled
    public var automaticallyChecksForUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: "automaticallyChecksForUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "automaticallyChecksForUpdates") }
    }

    // MARK: - Sparkle Integration (uncomment when Sparkle is added)

    /*
    import Sparkle

    private var updaterController: SPUStandardUpdaterController!

    public init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Set appcast URL if not in Info.plist
        if let appcastURL = URL(string: "https://cratebot.app/appcast.xml") {
            updaterController.updater.setFeedURL(appcastURL)
        }

        logger.info("UpdateManager initialized with Sparkle")
    }
    */

    public init() {
        logger.info("UpdateManager initialized (Sparkle not yet configured)")
    }

    /// Check for updates manually
    public func checkForUpdates() {
        logger.info("Checking for updates...")
        isChecking = true

        // Sparkle implementation:
        // updaterController.checkForUpdates(nil)

        // Placeholder until Sparkle is integrated
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isChecking = false
            self?.lastCheckDate = Date()
            self?.logger.info("Update check complete (Sparkle not configured)")
        }
    }

    /// Check for updates silently (no UI if no update)
    public func checkForUpdatesInBackground() {
        // Sparkle implementation:
        // updaterController.updater.checkForUpdatesInBackground()

        logger.debug("Background update check skipped (Sparkle not configured)")
    }

    /// Whether updates can be checked (Sparkle is configured)
    public var canCheckForUpdates: Bool {
        // Return true when Sparkle is properly configured
        // return updaterController.updater.canCheckForUpdates
        return false
    }
}

// MARK: - Sparkle Delegate (uncomment when Sparkle is added)

/*
extension UpdateManager: SPUUpdaterDelegate {

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        logger.info("Update available: \(item.displayVersionString)")
        updateAvailable = true
        availableVersion = item.displayVersionString
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        logger.debug("No update available")
        updateAvailable = false
        availableVersion = nil
    }

    public func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        isUpdating = true
    }

    public func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        logger.info("Downloaded update: \(item.displayVersionString)")
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        logger.error("Update aborted: \(error.localizedDescription)")
        isUpdating = false
    }

    public func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isChecking = false
        isUpdating = false
        lastCheckDate = Date()

        if let error = error {
            logger.warning("Update cycle finished with error: \(error.localizedDescription)")
        }
    }
}
*/
