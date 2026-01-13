import Foundation
import os.log

@Observable
public class BookmarkManager {
    private let bookmarksKey = "musicFolderBookmarks"
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.cratebot", category: "BookmarkManager")

    /// All registered music folder URLs with active access
    public private(set) var musicFolderURLs: [URL] = []

    /// Track which URLs have active security scope access
    private var activeAccessURLs: Set<URL> = []

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Persistence

    /// Save bookmark for a folder, adding to existing bookmarks
    public func addFolderAccess(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var bookmarks = loadBookmarkDictionary()
        bookmarks[url.path] = bookmark
        saveBookmarkDictionary(bookmarks)

        if url.startAccessingSecurityScopedResource() {
            activeAccessURLs.insert(url)
            if !musicFolderURLs.contains(url) {
                musicFolderURLs.append(url)
            }
            logger.info("Added folder access: \(url.path)")
        } else {
            logger.warning("Failed to start security scoped access for: \(url.path)")
        }
    }

    /// Remove a folder from bookmarks
    public func removeFolderAccess(_ url: URL) {
        var bookmarks = loadBookmarkDictionary()
        bookmarks.removeValue(forKey: url.path)
        saveBookmarkDictionary(bookmarks)

        if activeAccessURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeAccessURLs.remove(url)
        }
        musicFolderURLs.removeAll { $0 == url }
        logger.info("Removed folder access: \(url.path)")
    }

    // MARK: - Restoration

    public enum BookmarkRestoreResult: Equatable {
        case restored
        case refreshed
        case accessDenied
        case invalid(String)
    }

    /// Restore access to all saved bookmarks on app launch
    @discardableResult
    public func restoreAllAccess() -> [URL: BookmarkRestoreResult] {
        var results: [URL: BookmarkRestoreResult] = [:]
        let bookmarks = loadBookmarkDictionary()

        for (path, bookmarkData) in bookmarks {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    try addFolderAccess(url)
                    results[url] = .refreshed
                    logger.info("Refreshed stale bookmark: \(url.path)")
                } else if url.startAccessingSecurityScopedResource() {
                    activeAccessURLs.insert(url)
                    if !musicFolderURLs.contains(url) {
                        musicFolderURLs.append(url)
                    }
                    results[url] = .restored
                    logger.info("Restored bookmark: \(url.path)")
                } else {
                    results[url] = .accessDenied
                    logger.warning("Access denied for bookmark: \(url.path)")
                }
            } catch {
                let url = URL(fileURLWithPath: path)
                results[url] = .invalid(error.localizedDescription)
                logger.error("Invalid bookmark for path \(path): \(error.localizedDescription)")
            }
        }

        return results
    }

    // MARK: - Access Control

    /// Check if we have access to a specific file URL
    public func hasAccess(to fileURL: URL) -> Bool {
        let filePath = fileURL.standardized.path
        return musicFolderURLs.contains { folder in
            let folderPath = folder.standardized.path
            let normalizedFolder = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
            return filePath.hasPrefix(normalizedFolder) || filePath == folderPath
        }
    }

    /// Stop all security-scoped access (call on app terminate)
    public func stopAllAccess() {
        for url in activeAccessURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeAccessURLs.removeAll()
        logger.info("Stopped all security-scoped access")
    }

    // MARK: - Private

    private func loadBookmarkDictionary() -> [String: Data] {
        userDefaults.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }

    private func saveBookmarkDictionary(_ bookmarks: [String: Data]) {
        userDefaults.set(bookmarks, forKey: bookmarksKey)
    }
}
