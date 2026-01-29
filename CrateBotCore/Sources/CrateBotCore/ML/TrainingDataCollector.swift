import Foundation
import os.log

/// Actor that scans directories for MP3 files, reads their ID3 tags,
/// and creates TaggedTrack instances for ML training.
public actor TrainingDataCollector {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "TrainingDataCollector")

    // MARK: - Types

    /// Result of a training data collection operation.
    public struct CollectionResult: Sendable {
        /// The collected tagged tracks.
        public let tracks: [TaggedTrack]

        /// Total number of files scanned.
        public let scannedCount: Int

        /// Number of files that encountered errors.
        public let errorCount: Int

        /// Errors that occurred during collection.
        public let errors: [CollectionError]

        /// Files that were excluded during pre-flight validation
        public let excludedFiles: [ExcludedFile]

        public init(
            tracks: [TaggedTrack],
            scannedCount: Int,
            errorCount: Int,
            errors: [CollectionError],
            excludedFiles: [ExcludedFile] = []
        ) {
            self.tracks = tracks
            self.scannedCount = scannedCount
            self.errorCount = errorCount
            self.errors = errors
            self.excludedFiles = excludedFiles
        }
    }

    /// Information about a file that was excluded from training
    public struct ExcludedFile: Sendable {
        public let url: URL
        public let reason: String
        public let duration: Double?

        public init(url: URL, reason: String, duration: Double? = nil) {
            self.url = url
            self.reason = reason
            self.duration = duration
        }
    }

    /// Progress information during collection.
    public struct CollectionProgress: Sendable {
        /// Number of files processed so far.
        public let processed: Int

        /// Total number of files to process.
        public let total: Int

        /// URL of the file currently being processed.
        public let currentFile: URL?

        public init(processed: Int, total: Int, currentFile: URL?) {
            self.processed = processed
            self.total = total
            self.currentFile = currentFile
        }

        /// Progress as a fraction from 0.0 to 1.0.
        public var fraction: Double {
            guard total > 0 else { return 0.0 }
            return Double(processed) / Double(total)
        }
    }

    /// Error that occurred during collection for a specific file.
    public struct CollectionError: Sendable, Error {
        /// The file URL that caused the error.
        public let url: URL

        /// Description of the error.
        public let message: String

        public init(url: URL, message: String) {
            self.url = url
            self.message = message
        }
    }

    /// Reasons why a track's features were skipped during extraction
    public enum TrackSkipReason: String, Sendable {
        case featureDimensionMismatch = "Feature dimension mismatch"
        case nonFiniteFeatures = "Non-finite values in features"
        case audioTooShort = "Audio too short"
        case extractionFailed = "Feature extraction failed"
    }

    /// Information about a track whose features were skipped
    public struct SkippedFeatureTrack: Sendable {
        public let url: URL
        public let reason: TrackSkipReason
        public let details: String?

        public init(url: URL, reason: TrackSkipReason, details: String? = nil) {
            self.url = url
            self.reason = reason
            self.details = details
        }
    }

    // MARK: - Dependencies

    private let id3Manager: ID3Manager
    private let audioAnalyzer: AudioAnalyzer
    private let embeddingCache: EmbeddingCache

    // MARK: - Augmentation

    /// Configuration for feature augmentation during extraction
    public var augmentationConfig: AudioAugmenter.AugmentationConfig = .default

    // MARK: - Feature Extraction Configuration

    /// Configuration for feature extraction (segment sampling, feature config)
    /// This affects cache compatibility - changing it invalidates cached embeddings
    public let featureExtractionConfig: FeatureExtractionConfig

    /// Lazy-loaded CombinedFeatureExtractor - only created when extractFeatures is called
    private var _combinedExtractor: CombinedFeatureExtractor?
    private var _combinedExtractorInitError: Error?
    private var _combinedExtractorInitialized = false

    // MARK: - Initialization

    /// Creates a new TrainingDataCollector.
    ///
    /// - Parameters:
    ///   - id3Manager: The ID3 manager for reading tags. Defaults to a new instance.
    ///   - audioAnalyzer: The audio analyzer for loading audio. Defaults to a new instance.
    ///   - featureExtractionConfig: Configuration for feature extraction. Defaults to .default.
    public init(
        id3Manager: ID3Manager = ID3Manager(),
        audioAnalyzer: AudioAnalyzer = AudioAnalyzer(),
        featureExtractionConfig: FeatureExtractionConfig = .default
    ) {
        self.id3Manager = id3Manager
        self.audioAnalyzer = audioAnalyzer
        self.featureExtractionConfig = featureExtractionConfig
        self.embeddingCache = EmbeddingCache(extractionConfig: featureExtractionConfig)
    }

    /// Get or create the CombinedFeatureExtractor (lazy initialization)
    private func getCombinedExtractor() -> CombinedFeatureExtractor? {
        if !_combinedExtractorInitialized {
            _combinedExtractorInitialized = true
            do {
                _combinedExtractor = try CombinedFeatureExtractor(config: self.featureExtractionConfig.featureConfig)
                _combinedExtractorInitError = nil
                logger.info("CombinedFeatureExtractor initialized successfully with config: \(self.featureExtractionConfig.featureConfig.description) (lazy)")
                Self.debugLog("CombinedFeatureExtractor initialized successfully with config: \(self.featureExtractionConfig.featureConfig.description) (lazy)")
            } catch {
                _combinedExtractor = nil
                _combinedExtractorInitError = error
                logger.error("CombinedFeatureExtractor init failed: \(error.localizedDescription)")
                Self.debugLog("CombinedFeatureExtractor init FAILED: \(error.localizedDescription)")
            }
        }
        return _combinedExtractor
    }

    /// Get the CombinedFeatureExtractor init error if any
    private func getCombinedExtractorInitError() -> Error? {
        _ = getCombinedExtractor()  // Ensure initialized
        return _combinedExtractorInitError
    }

    /// Get the actual feature dimension being used by the extractor
    /// This may differ from the requested config if CLAP is unavailable
    public func getActualFeatureDimension() async -> Int {
        guard let extractor = getCombinedExtractor() else {
            // Fallback to requested config dimension
            return featureExtractionConfig.featureConfig.dimension
        }
        return await extractor.featureDimension
    }

    /// Write debug log to file (in app's container for sandbox compatibility)
    private static func debugLog(_ message: String) {
        // Use app support directory for sandbox compatibility
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let cratebotDir = appSupport.appendingPathComponent("CrateBot")
        try? FileManager.default.createDirectory(at: cratebotDir, withIntermediateDirectories: true)
        let logFile = cratebotDir.appendingPathComponent("debug.log")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.synchronize()  // Force flush to disk
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
        }
    }

    /// Log at the start of feature extraction
    private func logFeatureExtractionStart(trackCount: Int) {
        Self.debugLog("Starting feature extraction for \(trackCount) tracks")
    }

    // MARK: - Collection Methods

    /// Collects training data from the specified directories.
    ///
    /// Recursively scans for MP3 files, validates them for potential issues,
    /// reads their ID3 tags, and creates TaggedTrack instances.
    /// Files that would cause crashes (too large, buffer overflow) are excluded.
    /// Files without any tags are skipped.
    ///
    /// - Parameters:
    ///   - directories: The directories to scan for MP3 files.
    ///   - mapping: Configuration for which ID3 fields map to which categories.
    ///   - progress: Optional closure called with progress updates.
    /// - Returns: A CollectionResult containing the tracks and statistics.
    public func collectTrainingData(
        from directories: [URL],
        mapping: TagFieldMapping = .default,
        progress: (@Sendable (CollectionProgress) async -> Void)? = nil
    ) async -> CollectionResult {
        // Discover all MP3 files
        let mp3Files = discoverMP3Files(in: directories)
        let totalDiscovered = mp3Files.count

        // Phase 1: Pre-flight validation to exclude problematic files
        logger.info("Validating \(totalDiscovered) audio files...")

        var excludedFiles: [ExcludedFile] = []
        var validFiles: [URL] = []

        // Validate files concurrently
        let validationResults = await audioAnalyzer.validateFiles(at: mp3Files)

        for result in validationResults {
            if result.isValid {
                validFiles.append(result.url)
            } else {
                let reason = result.error?.localizedDescription ?? "Unknown validation error"
                excludedFiles.append(ExcludedFile(
                    url: result.url,
                    reason: reason,
                    duration: result.duration
                ))
                logger.warning("Excluding file: \(result.url.lastPathComponent) - \(reason)")
            }
        }

        if !excludedFiles.isEmpty {
            logger.info("Excluded \(excludedFiles.count) files that would cause issues")
        }

        // Phase 2: Collect tags from valid files
        var tracks: [TaggedTrack] = []
        var errors: [CollectionError] = []
        let total = validFiles.count

        // Report initial progress immediately
        if let progress = progress {
            await progress(CollectionProgress(
                processed: 0,
                total: total,
                currentFile: validFiles.first
            ))
        }

        for (index, fileURL) in validFiles.enumerated() {
            // Report progress
            if let progress = progress {
                await progress(CollectionProgress(
                    processed: index,
                    total: total,
                    currentFile: fileURL
                ))
            }

            do {
                let extractedTags = try await id3Manager.readTags(from: fileURL)
                let tagSet = convertToTagSet(extractedTags, mapping: mapping)

                // Skip files with no tags
                guard !tagSet.isEmpty else { continue }

                let track = TaggedTrack(
                    id: fileURL.path,
                    tags: tagSet,
                    features: nil
                )
                tracks.append(track)
            } catch {
                errors.append(CollectionError(
                    url: fileURL,
                    message: error.localizedDescription
                ))
            }
        }

        // Final progress update
        if let progress = progress {
            await progress(CollectionProgress(
                processed: total,
                total: total,
                currentFile: nil
            ))
        }

        return CollectionResult(
            tracks: tracks,
            scannedCount: totalDiscovered,
            errorCount: errors.count,
            errors: errors,
            excludedFiles: excludedFiles
        )
    }

    /// Discovers all unique tags and their counts from a collection of tracks.
    ///
    /// - Parameter tracks: The tracks to analyze.
    /// - Returns: A dictionary mapping tag names to their occurrence counts.
    public func discoverTags(from tracks: [TaggedTrack]) -> [String: Int] {
        var tagCounts: [String: Int] = [:]

        for track in tracks {
            for tag in track.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        return tagCounts
    }

    /// Result of categorized tag discovery.
    public struct CategorizedTagCounts: Sendable {
        public var genre: [String: Int] = [:]
        public var timing: [String: Int] = [:]
        public var mood: [String: Int] = [:]
        public var descriptive: [String: Int] = [:]
        public var totalFiles: Int = 0

        public init() {}
    }

    /// ID3 field identifiers for configurable mapping - comprehensive iTunes support
    public enum ID3FieldType: String, Sendable, CaseIterable {
        // Common fields
        case title          // TIT2 - Song title
        case artist         // TPE1 - Artist
        case albumArtist    // TPE2 - Album Artist (often repurposed)
        case album          // TALB - Album name
        case genre          // TCON - Genre
        case contentGroup   // TIT1 - Grouping
        case comments       // COMM - Comments
        case composer       // TCOM - Composer
        case subtitle       // TIT3 - Subtitle/Description
        case conductor      // TPE3 - Conductor
        case lyricist       // TEXT - Lyricist
        case fileOwner      // TOWN - File owner

        // Additional metadata fields
        case bpm            // TBPM - Beats per minute
        case year           // TYER/TDRC - Year
        case publisher      // TPUB - Publisher/Label
        case encodedBy      // TENC - Encoded by
        case copyright      // TCOP - Copyright
        case originalArtist // TOPE - Original artist

        public var displayName: String {
            switch self {
            case .title: return "Title"
            case .artist: return "Artist"
            case .albumArtist: return "Album Artist"
            case .album: return "Album"
            case .genre: return "Genre"
            case .contentGroup: return "Grouping"
            case .comments: return "Comments"
            case .composer: return "Composer"
            case .subtitle: return "Subtitle"
            case .conductor: return "Conductor"
            case .lyricist: return "Lyricist"
            case .fileOwner: return "File Owner"
            case .bpm: return "BPM"
            case .year: return "Year"
            case .publisher: return "Publisher"
            case .encodedBy: return "Encoded By"
            case .copyright: return "Copyright"
            case .originalArtist: return "Original Artist"
            }
        }

        public var frameID: String {
            switch self {
            case .title: return "TIT2"
            case .artist: return "TPE1"
            case .albumArtist: return "TPE2"
            case .album: return "TALB"
            case .genre: return "TCON"
            case .contentGroup: return "TIT1"
            case .comments: return "COMM"
            case .composer: return "TCOM"
            case .subtitle: return "TIT3"
            case .conductor: return "TPE3"
            case .lyricist: return "TEXT"
            case .fileOwner: return "TOWN"
            case .bpm: return "TBPM"
            case .year: return "TYER"
            case .publisher: return "TPUB"
            case .encodedBy: return "TENC"
            case .copyright: return "TCOP"
            case .originalArtist: return "TOPE"
            }
        }
    }

    /// Configuration for which ID3 fields map to which training categories
    public struct TagFieldMapping: Sendable {
        public var genreField: ID3FieldType
        public var timingField: ID3FieldType
        public var moodField: ID3FieldType
        public var descriptiveField: ID3FieldType

        public init(
            genreField: ID3FieldType = .genre,
            timingField: ID3FieldType = .album,
            moodField: ID3FieldType = .contentGroup,
            descriptiveField: ID3FieldType = .comments
        ) {
            self.genreField = genreField
            self.timingField = timingField
            self.moodField = moodField
            self.descriptiveField = descriptiveField
        }

        public static let `default` = TagFieldMapping()
    }

    /// Scans directories and discovers tags categorized by type.
    ///
    /// - Parameters:
    ///   - directories: The directories to scan for MP3 files.
    ///   - mapping: Configuration for which ID3 fields map to which categories.
    ///   - progress: Optional closure called with progress updates.
    /// - Returns: Categorized tag counts.
    public func discoverCategorizedTags(
        from directories: [URL],
        mapping: TagFieldMapping = .default,
        progress: (@Sendable (CollectionProgress) async -> Void)? = nil
    ) async -> CategorizedTagCounts {
        let mp3Files = discoverMP3Files(in: directories)
        var result = CategorizedTagCounts()
        result.totalFiles = mp3Files.count

        for (index, fileURL) in mp3Files.enumerated() {
            if let progress = progress {
                await progress(CollectionProgress(
                    processed: index,
                    total: mp3Files.count,
                    currentFile: fileURL
                ))
            }

            do {
                let tags = try await id3Manager.readTags(from: fileURL)

                // Extract value for each category based on configured field mapping
                if let value = getFieldValue(tags, field: mapping.genreField), !value.isEmpty {
                    result.genre[value.trimmingCharacters(in: .whitespaces), default: 0] += 1
                }
                if let value = getFieldValue(tags, field: mapping.timingField), !value.isEmpty {
                    result.timing[value.trimmingCharacters(in: .whitespaces), default: 0] += 1
                }
                if let value = getFieldValue(tags, field: mapping.moodField), !value.isEmpty {
                    result.mood[value.trimmingCharacters(in: .whitespaces), default: 0] += 1
                }
                // Descriptive field: parse comma-separated values into individual tags
                if let value = getFieldValue(tags, field: mapping.descriptiveField), !value.isEmpty {
                    let individualTags = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    for tag in individualTags where !tag.isEmpty {
                        result.descriptive[tag, default: 0] += 1
                    }
                }
            } catch {
                // Skip files with read errors
                continue
            }
        }

        if let progress = progress {
            await progress(CollectionProgress(
                processed: mp3Files.count,
                total: mp3Files.count,
                currentFile: nil
            ))
        }

        return result
    }

    /// Gets the value of a specific ID3 field from extracted tags
    private func getFieldValue(_ tags: ExtractedTags, field: ID3FieldType) -> String? {
        let rawValue: String?
        switch field {
        case .title:
            rawValue = tags.title
        case .artist:
            rawValue = tags.artist
        case .albumArtist:
            rawValue = tags.albumArtist
        case .album:
            rawValue = tags.album ?? tags.timing  // Fall back to timing for backwards compat
        case .genre:
            rawValue = tags.genre
        case .contentGroup:
            rawValue = tags.mood    // TIT1 is mapped to mood in ExtractedTags
        case .comments:
            rawValue = tags.comments
        case .composer:
            rawValue = tags.vibeShort  // TCOM is mapped to vibeShort
        case .subtitle:
            rawValue = tags.vibeDescription  // TIT3 is mapped to vibeDescription
        case .conductor:
            rawValue = tags.conductor
        case .lyricist:
            rawValue = tags.hook    // TEXT is mapped to hook
        case .fileOwner:
            rawValue = tags.scene   // TOWN is mapped to scene
        case .bpm:
            rawValue = tags.bpm
        case .year:
            rawValue = tags.year
        case .publisher:
            rawValue = tags.publisher
        case .encodedBy:
            rawValue = tags.encodedBy
        case .copyright:
            rawValue = tags.copyright
        case .originalArtist:
            rawValue = tags.originalArtist
        }

        // Sanitize the value - remove non-printable characters and ID3v1 artifacts
        guard let value = rawValue else { return nil }
        return sanitizeTagValue(value)
    }

    /// Sanitizes a tag value by removing non-printable characters and ID3v1 artifacts
    private func sanitizeTagValue(_ value: String) -> String? {
        // Filter out non-printable characters (keep printable ASCII and common unicode)
        let sanitized = value.unicodeScalars.filter { scalar in
            // Keep printable ASCII (space through tilde), plus common punctuation/letters
            (scalar.value >= 32 && scalar.value <= 126) ||  // Basic printable ASCII
            scalar.properties.isAlphabetic ||               // Letters from any language
            scalar.properties.isWhitespace ||               // Whitespace
            CharacterSet.punctuationCharacters.contains(scalar)  // Punctuation
        }

        let result = String(String.UnicodeScalarView(sanitized))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter out strings that look like binary garbage or ID3v1 artifacts
        guard !result.isEmpty else { return nil }

        // Filter out ID3v1 comment artifacts (often have "ID3v1 Comment" or similar prefixes)
        let lowercased = result.lowercased()
        if lowercased.contains("id3v1") || lowercased.contains("id3 comment") {
            return nil
        }

        // Filter out common iTunes/encoder artifacts
        let artifactPatterns = ["itunes", "lame", "encoded", "ripped", "mp3", "www.", "http"]
        for pattern in artifactPatterns {
            if lowercased.hasPrefix(pattern) {
                return nil
            }
        }

        // If the result is mostly non-letter characters, it's probably garbage
        let letterCount = result.unicodeScalars.filter { $0.properties.isAlphabetic }.count
        let totalCount = result.count
        if totalCount > 3 && Double(letterCount) / Double(totalCount) < 0.3 {
            return nil  // Less than 30% letters = probably garbage
        }

        // Filter out very long strings that are likely garbage (real tags are usually short)
        if result.count > 100 {
            return nil
        }

        return result
    }

    /// Extracts audio features for tracks that don't already have them.
    ///
    /// Uses CombinedFeatureExtractor to generate features from audio based on featureExtractionConfig:
    /// - .effnetOnly: 1280 dims (EffNet embeddings)
    /// - .effnetPlusGenres: 1680 dims (1280 embeddings + 400 genre activations)
    /// - .effnetGenresCLAP: 2192 dims (1280 + 400 + 512 CLAP embeddings)
    ///
    /// Audio is loaded at 16kHz for EffNet processing.
    /// Uses concurrent batch processing for improved performance.
    ///
    /// - Parameters:
    ///   - tracks: The tracks to extract features for.
    ///   - concurrency: Number of tracks to process in parallel (default 8).
    ///   - progress: Optional closure called with progress updates.
    /// - Returns: An array of tracks with features populated.
    public func extractFeatures(
        for tracks: [TaggedTrack],
        concurrency: Int = 8,
        progress: (@Sendable (CollectionProgress) async -> Void)? = nil
    ) async -> [TaggedTrack] {
        // Delegate to checkpoint-aware version without checkpointing
        await extractFeatures(
            for: tracks,
            concurrency: concurrency,
            modelName: nil,
            sourceDirectories: [],
            checkpointManager: nil,
            progress: progress
        )
    }

    /// Extracts audio features with checkpoint support for resumable training.
    ///
    /// Uses CombinedFeatureExtractor to generate features from audio based on featureExtractionConfig:
    /// - .effnetOnly: 1280 dims (EffNet embeddings)
    /// - .effnetPlusGenres: 1680 dims (1280 embeddings + 400 genre activations)
    /// - .effnetGenresCLAP: 2192 dims (1280 + 400 + 512 CLAP embeddings)
    ///
    /// Saves checkpoints every 50 tracks so training can resume if interrupted.
    ///
    /// - Parameters:
    ///   - tracks: The tracks to extract features for.
    ///   - concurrency: Number of tracks to process in parallel (default 8).
    ///   - modelName: Name of the model being trained (for checkpoint identification).
    ///   - sourceDirectories: Source directories for this training run.
    ///   - checkpointManager: Manager for saving/loading checkpoints.
    ///   - progress: Optional closure called with progress updates.
    /// - Returns: An array of tracks with features populated.
    public func extractFeatures(
        for tracks: [TaggedTrack],
        concurrency: Int = 8,
        modelName: String?,
        sourceDirectories: [URL],
        checkpointManager: CheckpointManager?,
        progress: (@Sendable (CollectionProgress) async -> Void)? = nil
    ) async -> [TaggedTrack] {
        Self.debugLog("extractFeatures called with \(tracks.count) tracks, concurrency: \(concurrency)")
        let total = tracks.count

        // Report initial progress immediately so UI shows total count
        if let progress = progress {
            await progress(CollectionProgress(
                processed: 0,
                total: total,
                currentFile: nil
            ))
        }

        // Ensure extractor is initialized before concurrent work
        guard let extractor = getCombinedExtractor() else {
            if let initError = getCombinedExtractorInitError() {
                Self.debugLog("No extractor available, init error: \(initError)")
            }
            Self.debugLog("No extractor available, returning tracks without features")
            return tracks
        }

        // Separate tracks that already have features
        let tracksNeedingFeatures = tracks.filter { $0.features == nil }
        let tracksWithFeatures = tracks.filter { $0.features != nil }

        Self.debugLog("\(tracksWithFeatures.count) tracks already have features, extracting for \(tracksNeedingFeatures.count)")

        if tracksNeedingFeatures.isEmpty {
            // Report completion
            if let progress = progress {
                await progress(CollectionProgress(
                    processed: total,
                    total: total,
                    currentFile: nil
                ))
            }
            return tracks
        }

        // Phase 1: Check cache for already-computed embeddings
        var cachedTracks: [TaggedTrack] = []
        var uncachedTracks: [TaggedTrack] = []

        for track in tracksNeedingFeatures {
            let fileURL = URL(fileURLWithPath: track.id)
            if let cachedFeatures = await embeddingCache.get(for: fileURL) {
                let updatedTrack = TaggedTrack(id: track.id, tags: track.tags, features: cachedFeatures)
                cachedTracks.append(updatedTrack)
            } else {
                uncachedTracks.append(track)
            }
        }

        let cacheStats = await embeddingCache.statistics
        Self.debugLog("Cache check: \(cachedTracks.count) hits, \(uncachedTracks.count) misses (total cache entries: \(cacheStats.totalEntries))")

        // Phase 2: Process uncached tracks with concurrent individual inference
        // (Batch inference not supported by this CoreML model's fixed input shape)
        var extractedTracks: [TaggedTrack] = cachedTracks
        var processedSoFar = tracksWithFeatures.count + cachedTracks.count

        // Report initial progress
        if let progress = progress {
            await progress(CollectionProgress(
                processed: processedSoFar,
                total: total,
                currentFile: uncachedTracks.first.map { URL(fileURLWithPath: $0.id) }
            ))
        }

        // Process in concurrent batches
        let batchSize = max(1, concurrency)

        for batchStart in stride(from: 0, to: uncachedTracks.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, uncachedTracks.count)
            let batch = Array(uncachedTracks[batchStart..<batchEnd])

            // Report progress at batch start
            if let progress = progress, !batch.isEmpty {
                await progress(CollectionProgress(
                    processed: processedSoFar,
                    total: total,
                    currentFile: URL(fileURLWithPath: batch[0].id)
                ))
            }

            // Process batch concurrently - load audio and extract features in one step
            // Capture augmentation config and expected feature dimension for use in task group
            let augConfig = self.augmentationConfig
            let expectedDimension = await extractor.featureDimension
            let segmentDuration = self.featureExtractionConfig.segmentDuration
            let startFractions = self.featureExtractionConfig.segmentStartFractions
            let batchResults = await withTaskGroup(of: (Int, TaggedTrack, [Float]?).self) { group in
                for (localIndex, track) in batch.enumerated() {
                    group.addTask { [audioAnalyzer, extractor, segmentDuration, startFractions] in
                        let globalIndex = batchStart + localIndex
                        do {
                            let fileURL = URL(fileURLWithPath: track.id)
                            let buffers = try await audioAnalyzer.loadAudioSegments(
                                from: fileURL,
                                targetSampleRate: EffNetExtractor.targetSampleRate,
                                segmentDuration: segmentDuration,
                                startFractions: startFractions
                            )

                            var segmentFeatures: [[Float]] = []
                            segmentFeatures.reserveCapacity(buffers.count)

                            for buffer in buffers {
                                // Use CombinedFeatureExtractor for unified feature extraction
                                let features = try await extractor.extract(from: buffer)

                                // Validate feature dimensions
                                if features.count != expectedDimension {
                                    Self.debugLog("Track \(fileURL.lastPathComponent) has \(features.count) features, expected \(expectedDimension) - skipping segment")
                                    continue
                                }

                                // Validate no NaN/Inf values
                                if features.contains(where: { !$0.isFinite }) {
                                    Self.debugLog("Track \(fileURL.lastPathComponent) has non-finite features - skipping segment")
                                    continue
                                }

                                segmentFeatures.append(features)
                            }

                            guard let averaged = Self.averageFeatures(segmentFeatures, expectedDimension: expectedDimension) else {
                                Self.debugLog("Track \(fileURL.lastPathComponent) produced no valid segments - skipping")
                                return (globalIndex, track, nil)
                            }

                            // Apply feature-level augmentation for training robustness
                            let augmentedFeatures = AudioAugmenter.augmentFeatures(
                                averaged,
                                addNoise: augConfig.featureNoiseEnabled,
                                noiseScale: augConfig.featureNoiseScale
                            )
                            return (globalIndex, track, augmentedFeatures)
                        } catch {
                            Self.debugLog("Track \(URL(fileURLWithPath: track.id).lastPathComponent) extraction failed: \(error.localizedDescription)")
                            return (globalIndex, track, nil)
                        }
                    }
                }

                var results: [(Int, TaggedTrack, [Float]?)] = []
                for await result in group {
                    results.append(result)
                }
                return results.sorted { $0.0 < $1.0 }
            }

            // Combine results and cache
            for (_, track, features) in batchResults {
                if let features = features, !features.isEmpty {
                    let updatedTrack = TaggedTrack(id: track.id, tags: track.tags, features: features)
                    extractedTracks.append(updatedTrack)

                    // Cache the embeddings
                    let fileURL = URL(fileURLWithPath: track.id)
                    await embeddingCache.set(features, for: fileURL)
                } else {
                    // Failed to extract features - keep track without features
                    extractedTracks.append(track)
                }
            }

            processedSoFar += batch.count

            // Report progress after batch completes
            if let progress = progress {
                await progress(CollectionProgress(
                    processed: processedSoFar,
                    total: total,
                    currentFile: batch.last.map { URL(fileURLWithPath: $0.id) }
                ))
            }

            // Save checkpoint every 50 tracks (if checkpointing enabled)
            if let modelName = modelName,
               let checkpointManager = checkpointManager,
               extractedTracks.count % CheckpointManager.saveInterval == 0 {
                // Combine with tracks that already had features
                let tracksForCheckpoint = tracksWithFeatures + extractedTracks
                let checkpoint = TrainingCheckpoint(
                    modelName: modelName,
                    sourceDirectories: sourceDirectories,
                    processedTracks: tracksForCheckpoint,
                    totalTracksDiscovered: total
                )
                do {
                    try checkpointManager.save(checkpoint)
                    Self.debugLog("Saved checkpoint at \(extractedTracks.count) tracks")
                } catch {
                    Self.debugLog("Failed to save checkpoint: \(error.localizedDescription)")
                }
            }
        }

        // Save embedding cache
        await embeddingCache.saveIfNeeded()

        // Combine tracks with existing features and newly extracted
        var allTracks: [TaggedTrack] = []
        var extractedIndex = 0

        for track in tracks {
            if track.features != nil {
                allTracks.append(track)
            } else {
                allTracks.append(extractedTracks[extractedIndex])
                extractedIndex += 1
            }
        }

        // Final progress update
        if let progress = progress {
            await progress(CollectionProgress(
                processed: total,
                total: total,
                currentFile: nil
            ))
        }

        Self.debugLog("Feature extraction complete: \(allTracks.filter { $0.features != nil }.count)/\(total) tracks have features")

        // Save final checkpoint with all processed tracks
        if let modelName = modelName,
           let checkpointManager = checkpointManager {
            let checkpoint = TrainingCheckpoint(
                modelName: modelName,
                sourceDirectories: sourceDirectories,
                processedTracks: allTracks.filter { $0.features != nil },
                totalTracksDiscovered: total
            )
            do {
                try checkpointManager.save(checkpoint)
                Self.debugLog("Saved final checkpoint with \(checkpoint.processedTracks.count) tracks")
            } catch {
                Self.debugLog("Failed to save final checkpoint: \(error.localizedDescription)")
            }
        }

        return allTracks
    }

    // MARK: - Private Helpers

    /// Recursively discovers all MP3 files in the given directories.
    private func discoverMP3Files(in directories: [URL]) -> [URL] {
        var mp3Files: [URL] = []
        let fileManager = FileManager.default

        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension.lowercased() == "mp3" {
                    mp3Files.append(fileURL)
                }
            }
        }

        return mp3Files
    }

    /// Converts ExtractedTags to a Set<String> for TaggedTrack using the configured field mapping.
    ///
    /// - Parameters:
    ///   - tags: The extracted ID3 tags from the file.
    ///   - mapping: Configuration for which ID3 fields map to which training categories.
    /// - Returns: A set of tag strings to use for training.
    private func convertToTagSet(_ tags: ExtractedTags, mapping: TagFieldMapping) -> Set<String> {
        var tagSet = Set<String>()

        // Add genre from mapped field (single value)
        if let value = getFieldValue(tags, field: mapping.genreField), !value.isEmpty {
            tagSet.insert(value.trimmingCharacters(in: .whitespaces))
        }

        // Add timing from mapped field (single value)
        if let value = getFieldValue(tags, field: mapping.timingField), !value.isEmpty {
            tagSet.insert(value.trimmingCharacters(in: .whitespaces))
        }

        // Add mood from mapped field (single value)
        if let value = getFieldValue(tags, field: mapping.moodField), !value.isEmpty {
            tagSet.insert(value.trimmingCharacters(in: .whitespaces))
        }

        // Add descriptive tags from mapped field (comma-separated values)
        if let value = getFieldValue(tags, field: mapping.descriptiveField), !value.isEmpty {
            // Parse comma-separated tags
            let individualTags = value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            for tag in individualTags where !tag.isEmpty {
                tagSet.insert(tag)
            }
        }

        return tagSet
    }

    private static func averageFeatures(_ segments: [[Float]], expectedDimension: Int) -> [Float]? {
        guard !segments.isEmpty else { return nil }
        var sums = [Double](repeating: 0.0, count: expectedDimension)
        var count = 0

        for features in segments {
            guard features.count == expectedDimension else { continue }
            for i in 0..<expectedDimension {
                sums[i] += Double(features[i])
            }
            count += 1
        }

        guard count > 0 else { return nil }

        return sums.map { Float($0 / Double(count)) }
    }
}
