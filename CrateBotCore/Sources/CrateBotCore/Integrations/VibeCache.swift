import Foundation
import CryptoKit
import os.log

/// Persistent cache for `VibeGeneratorV2` results.
///
/// Keyed by `SHA256(trackPath | stage1ModelVersion)` so a re-tag of the same
/// file under the same Stage 1 model is free, and any change to either input
/// invalidates the entry. Pricing context: each generation costs ~$0.01, so
/// the cache pays for itself the first time the user re-tags anything.
///
/// Storage: JSON file at `Application Support/CrateBot/vibe_cache.json`
/// (matching `EmbeddingCache`/`ModelManager`). Single dict on disk; loaded
/// synchronously on init, atomic write on every save. No eviction in v1 —
/// logs a warning when the file grows past 10 MB.
public actor VibeCache {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "VibeCache")
    private let cacheURL: URL
    private var cache: [String: VibeGenerationResult] = [:]
    private var hits = 0
    private var misses = 0

    /// Soft cap; we log past this size but do not evict.
    private static let sizeWarningBytes: Int = 10 * 1024 * 1024

    // MARK: - Initialization

    public init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cratebotDir = appSupport.appendingPathComponent("CrateBot")
        try? FileManager.default.createDirectory(at: cratebotDir, withIntermediateDirectories: true)
        self.cacheURL = cratebotDir.appendingPathComponent("vibe_cache.json")
        self.cache = Self.load(from: cacheURL, logger: logger)
    }

    /// Test-only initializer that allows overriding the cache file location.
    /// Mark `internal` so `@testable import` reaches it without exposing it
    /// to production callers.
    internal init(cacheURL: URL) {
        self.cacheURL = cacheURL
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.cache = Self.load(from: cacheURL, logger: logger)
    }

    // MARK: - Public API

    public func get(trackPath: String, stage1ModelVersion: String) -> VibeGenerationResult? {
        let k = Self.key(trackPath: trackPath, stage1ModelVersion: stage1ModelVersion)
        if let hit = cache[k] {
            hits += 1
            return hit
        }
        misses += 1
        return nil
    }

    public func set(
        _ result: VibeGenerationResult,
        trackPath: String,
        stage1ModelVersion: String
    ) async {
        let k = Self.key(trackPath: trackPath, stage1ModelVersion: stage1ModelVersion)
        cache[k] = result
        save()
    }

    public func count() -> Int { cache.count }

    public func clear() async {
        cache.removeAll()
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: - Key derivation

    /// Returns the hex SHA256 of `"{trackPath}|{stage1ModelVersion}"`.
    private static func key(trackPath: String, stage1ModelVersion: String) -> String {
        let composite = "\(trackPath)|\(stage1ModelVersion)"
        let digest = SHA256.hash(data: Data(composite.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistence

    private static func load(from url: URL, logger: Logger) -> [String: VibeGenerationResult] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: VibeGenerationResult].self, from: data)
        } catch {
            logger.warning("vibe_cache.json could not be decoded (\(error.localizedDescription, privacy: .public)); starting empty")
            return [:]
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(cache)
            // Atomic write so a crash mid-write cannot corrupt the cache.
            try data.write(to: cacheURL, options: .atomic)
            if data.count > Self.sizeWarningBytes {
                let mb = Double(data.count) / (1024.0 * 1024.0)
                logger.error("vibe_cache.json size \(mb, format: .fixed(precision: 1)) MB exceeds soft limit; eviction not implemented")
            }
        } catch {
            logger.error("Failed to persist vibe_cache.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
