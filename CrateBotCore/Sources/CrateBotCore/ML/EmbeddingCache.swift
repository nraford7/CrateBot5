import Foundation
import os.log

/// Persistent cache for audio embeddings to avoid re-extracting features for unchanged files.
/// Embeddings are keyed by file path, modification date, AND extraction config hash,
/// so changed files or changed extraction parameters get re-extracted.
public actor EmbeddingCache {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "EmbeddingCache")

    /// Cache entry containing embeddings and metadata
    private struct CacheEntry: Codable {
        let embeddings: [Float]
        let modificationDate: Date
        let extractorVersion: String
        let configHash: String  // Extraction config hash for cache invalidation
    }

    /// In-memory cache (loaded from disk on init)
    private var cache: [String: CacheEntry] = [:]

    /// Whether cache has been modified since last save
    private var isDirty = false

    /// Cache file URL
    private let cacheURL: URL

    /// Current extractor version (cache invalidates if version changes)
    private let extractorVersion: String

    /// Current extraction config hash (cache invalidates if config changes)
    private let configHash: String

    /// Statistics
    private var hits = 0
    private var misses = 0

    // MARK: - Initialization

    public init(
        extractionConfig: FeatureExtractionConfig = .default,
        extractorVersion: String = "effnet-v2-extended-2192"
    ) {
        self.extractorVersion = extractorVersion
        self.configHash = extractionConfig.configHash

        // Store cache in Application Support/CrateBot/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cratebotDir = appSupport.appendingPathComponent("CrateBot")
        try? FileManager.default.createDirectory(at: cratebotDir, withIntermediateDirectories: true)
        self.cacheURL = cratebotDir.appendingPathComponent("embedding_cache.json")

        // Load existing cache synchronously in init (cache is local to this actor)
        if FileManager.default.fileExists(atPath: cacheURL.path),
           let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let loaded = try? decoder.decode([String: CacheEntry].self, from: data) {
                self.cache = loaded
            }
        }
    }

    // MARK: - Public API

    /// Get cached embeddings for a file, if available and still valid
    /// - Parameter url: URL of the audio file
    /// - Returns: Cached embeddings if valid, nil otherwise
    public func get(for url: URL) -> [Float]? {
        let key = url.path

        guard let entry = cache[key] else {
            misses += 1
            return nil
        }

        // Check if file has been modified since caching
        guard let currentModDate = getModificationDate(for: url) else {
            misses += 1
            return nil
        }

        // Check modification date matches (within 1 second tolerance)
        let timeDiff = abs(entry.modificationDate.timeIntervalSince(currentModDate))
        guard timeDiff < 1.0 else {
            misses += 1
            logger.debug("Cache miss (modified): \(url.lastPathComponent)")
            return nil
        }

        // Check extractor version matches
        guard entry.extractorVersion == extractorVersion else {
            misses += 1
            logger.debug("Cache miss (version): \(url.lastPathComponent)")
            return nil
        }

        // Check extraction config hash matches
        guard entry.configHash == configHash else {
            misses += 1
            logger.debug("Cache miss (config): \(url.lastPathComponent)")
            return nil
        }

        hits += 1
        return entry.embeddings
    }

    /// Store embeddings for a file in the cache
    /// - Parameters:
    ///   - embeddings: The extracted embeddings
    ///   - url: URL of the audio file
    public func set(_ embeddings: [Float], for url: URL) {
        guard let modDate = getModificationDate(for: url) else {
            return
        }

        let entry = CacheEntry(
            embeddings: embeddings,
            modificationDate: modDate,
            extractorVersion: extractorVersion,
            configHash: configHash
        )

        cache[url.path] = entry
        isDirty = true
    }

    /// Save cache to disk if modified
    public func saveIfNeeded() {
        guard isDirty else { return }
        saveToDisk()
    }

    /// Force save cache to disk
    public func save() {
        saveToDisk()
    }

    /// Clear all cached embeddings
    public func clear() {
        cache.removeAll()
        isDirty = true
        saveToDisk()
        logger.info("Embedding cache cleared")
    }

    /// Get cache statistics
    public var statistics: (hits: Int, misses: Int, totalEntries: Int) {
        (hits, misses, cache.count)
    }

    /// Reset statistics counters
    public func resetStatistics() {
        hits = 0
        misses = 0
    }

    // MARK: - Private Helpers

    private func getModificationDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            logger.info("No existing embedding cache found")
            return
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = try decoder.decode([String: CacheEntry].self, from: data)
            logger.info("Loaded \(self.cache.count) cached embeddings")
        } catch {
            logger.error("Failed to load embedding cache: \(error.localizedDescription)")
            cache = [:]
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            isDirty = false
            logger.info("Saved \(self.cache.count) embeddings to cache")
        } catch {
            logger.error("Failed to save embedding cache: \(error.localizedDescription)")
        }
    }
}
