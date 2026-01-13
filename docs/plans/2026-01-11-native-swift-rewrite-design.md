# CrateBot Native Swift Rewrite Design

**Date:** 2026-01-11
**Status:** Approved
**Goal:** Rebuild CrateBot as a native macOS app using Swift/SwiftUI and CoreML for improved stability, performance, and distribution.

---

## Problem Statement

The current CrateBot4 architecture (Electron + React frontend, Python FastAPI backend) causes:
- Stability issues (server crashes, connection drops, startup failures)
- Development friction (hard to debug, slow iteration, complex build)
- Performance problems (slow startup, high memory, sluggish UI)
- Distribution challenges (400MB+ app size, signing/notarization complexity)

## Solution

Rewrite as a pure Swift/SwiftUI macOS application with CoreML for machine learning, eliminating the two-runtime hybrid architecture.

---

## Requirements & Constraints

### Minimum macOS Version: 14 (Sonoma)

This enables:
- SwiftData for persistence
- @Observable for state management
- Create ML training APIs
- Modern Swift concurrency

### Sandbox: Enabled with Security-Scoped Bookmarks

Entitlements required:
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    CrateBot.app                         │
├─────────────────────────────────────────────────────────┤
│  UI Layer (SwiftUI)                                     │
│  ├── SetupWizard, TaggingView, TrainView, RefineView   │
│  ├── Native file pickers, drag-drop, audio player      │
│  └── State management via @Observable / SwiftData      │
├─────────────────────────────────────────────────────────┤
│  Audio Engine (AVFoundation + Accelerate)              │
│  ├── AudioAnalyzer (AVAudioEngine for extraction)      │
│  ├── AudioPlayer (AVAudioPlayer for playback)          │
│  ├── Feature extraction (vDSP for FFT, MFCC, etc.)     │
│  └── Waveform rendering (native Canvas)                │
├─────────────────────────────────────────────────────────┤
│  ML Layer (CoreML + Create ML)                          │
│  ├── GenreClassifier.mlmodel (single-label)            │
│  ├── TimingClassifier.mlmodel (single-label)           │
│  ├── MoodClassifiers/ (binary per tag)                 │
│  └── DescriptiveClassifiers/ (binary per tag)          │
├─────────────────────────────────────────────────────────┤
│  Data Layer (SwiftData + UserDefaults + Keychain)      │
│  ├── Feature cache (compressed, versioned)             │
│  ├── Override store (corrections)                      │
│  ├── Security-scoped bookmarks                         │
│  └── App settings                                       │
└─────────────────────────────────────────────────────────┘
```

---

## Two-App Strategy

### CrateBot Model Lab (Dev Tool)
Your personal tool for experimentation:
- Feature extractor testing (individual, ablation, ensemble)
- Subset sampling (100/250 songs for fast iteration)
- Accuracy comparisons with detailed reports
- Binary classifier threshold tuning
- Determine which tags have sufficient training data (min ~50 positive examples)
- Export winning configuration for main app

### CrateBot (User App)
The production app for distribution:
- Clean tagging UI
- Ships with baseline models (your pre-trained)
- Optional fine-tuning on user's library
- Batch tagging with progress
- Refinement workflow

Both apps share `CrateBotCore` Swift package.

---

## Multi-Label ML Architecture

### Training Strategy: Baseline + Local Fine-tuning

- Ship pre-trained models from your library
- Users get instant predictions on first launch
- Optional: users tag songs and retrain to improve accuracy for their collection

### Classifier Structure

| Category | Type | Models |
|----------|------|--------|
| Genre | Single-label | 1 classifier (e.g., "House", "Techno", "Disco") |
| Timing | Single-label | 1 classifier (e.g., "Opener", "Peak", "Closer") |
| Mood | Multi-label | N binary classifiers (1 per mood tag) |
| Descriptive | Multi-label | M binary classifiers (1 per descriptive tag) |

### Training Data Preparation

**Positive/Negative Sampling for Binary Classifiers:**

```swift
struct BinaryTrainingDataGenerator {
    /// Minimum positive examples required to train a tag classifier
    static let minPositiveExamples = 50

    /// Maximum negative:positive ratio to prevent class imbalance
    static let maxNegativeRatio = 3.0

    func generateTrainingData(
        for tagName: String,
        from tracks: [TaggedTrack]
    ) -> (positive: [TaggedTrack], negative: [TaggedTrack])? {
        let positive = tracks.filter { $0.tags.contains(tagName) }
        let negative = tracks.filter { !$0.tags.contains(tagName) }

        // Skip tags with insufficient data
        guard positive.count >= Self.minPositiveExamples else {
            return nil
        }

        // Balance negative samples to avoid overwhelming positives
        let maxNegatives = Int(Double(positive.count) * Self.maxNegativeRatio)
        let balancedNegative = Array(negative.shuffled().prefix(maxNegatives))

        return (positive, balancedNegative)
    }
}
```

**Threshold Selection via Validation:**

```swift
struct ThresholdOptimizer {
    /// Find optimal threshold using validation set
    func optimizeThreshold(
        predictions: [(confidence: Float, isPositive: Bool)],
        metric: OptimizationMetric = .f1Score
    ) -> Float {
        let candidates: [Float] = stride(from: 0.3, to: 0.8, by: 0.05).map { Float($0) }

        return candidates.max { threshold1, threshold2 in
            score(predictions, at: threshold1, metric: metric) <
            score(predictions, at: threshold2, metric: metric)
        } ?? 0.5
    }

    enum OptimizationMetric {
        case f1Score      // Balance precision/recall
        case precision    // Minimize false positives (fewer wrong tags)
        case recall       // Minimize false negatives (don't miss tags)
    }
}
```

**Tag Viability Criteria (determined in Model Lab):**
- Minimum 50 positive examples
- Validation F1 score > 0.6
- Consistent predictions across feature extractors

### Binary Classifier Pattern (CoreML)

```swift
/// Wrapper for CoreML binary classifier with proper MLFeatureProvider usage
class TagClassifier {
    let tagName: String
    let compiledModel: MLModel
    let threshold: Float
    let featureInputKey: String   // e.g., "features" - from model spec
    let probabilityOutputKey: String  // e.g., "probability" - from model spec

    init(tagName: String, modelURL: URL, threshold: Float) throws {
        self.tagName = tagName
        self.compiledModel = try MLModel(contentsOf: modelURL)
        self.threshold = threshold

        // Extract input/output keys from model description
        let description = compiledModel.modelDescription
        self.featureInputKey = description.inputDescriptionsByName.keys.first!
        self.probabilityOutputKey = description.outputDescriptionsByName
            .first { $0.value.type == .dictionary }?.key ?? "probability"
    }

    func predict(features: [Float]) throws -> Bool {
        // Create MLMultiArray for input features
        let multiArray = try MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .float32)
        for (i, value) in features.enumerated() {
            multiArray[i] = NSNumber(value: value)
        }

        // Create feature provider
        let inputProvider = try MLDictionaryFeatureProvider(dictionary: [
            featureInputKey: MLFeatureValue(multiArray: multiArray)
        ])

        // Run prediction
        let output = try compiledModel.prediction(from: inputProvider)

        // Extract probability for positive class
        guard let probabilityDict = output.featureValue(for: probabilityOutputKey)?.dictionaryValue,
              let positiveProb = probabilityDict["positive"] as? Double else {
            throw TagClassifierError.invalidOutput
        }

        return Float(positiveProb) > threshold
    }
}

class MultiLabelPredictor {
    let classifiers: [TagClassifier]

    func predict(features: [Float]) throws -> [String] {
        try classifiers
            .filter { try $0.predict(features: features) }
            .map { $0.tagName }
    }
}

enum TagClassifierError: Error {
    case invalidOutput
    case featureDimensionMismatch
}
```

### Model Metadata

```swift
struct ModelMetadata: Codable {
    let extractorsUsed: [String]
    let extractorVersion: String
    let featureCount: Int
    let trainedDate: Date
    let accuracyMetrics: [String: Double]
    let threshold: Float  // For binary classifiers
}
```

---

## Feature Extraction

### Extensible Architecture

```swift
protocol FeatureExtractor {
    var id: String { get }
    var version: String { get }
    var featureCount: Int { get }
    func extract(from buffer: AVAudioPCMBuffer) async throws -> [Float]
}
```

### Phase 1 Extractors (Bundled)
| Extractor | Features | Implementation |
|-----------|----------|----------------|
| SpectralExtractor | MFCCs, chroma, spectral stats | Accelerate/vDSP |
| AppleSoundAnalysisExtractor | Built-in sound classification | SoundAnalysis framework |

### Phase 2 Extractors (On-Demand Download)
| Extractor | Features | Size | Implementation |
|-----------|----------|------|----------------|
| PANNsExtractor | Audio tagging embeddings | ~150MB | CoreML-converted model |
| CLAPExtractor | Semantic audio embeddings | ~200MB | CoreML-converted model |

---

## Audio Architecture

### Separation of Analysis vs Playback

```swift
// ANALYSIS: Deterministic extraction via AVAudioConverter with streaming
class AudioAnalyzer {
    private let targetSampleRate: Double = 22050
    private let chunkSize: AVAudioFrameCount = 8192

    enum AnalyzerError: Error {
        case conversionFailed
        case formatCreationFailed
    }

    func extractPCMBuffer(from url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)

        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: 1  // Mono for analysis
        ) else {
            throw AnalyzerError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
            throw AnalyzerError.formatCreationFailed
        }

        // Calculate output frame count
        let outputFrameCount = AVAudioFrameCount(
            Double(file.length) * targetSampleRate / file.processingFormat.sampleRate
        )

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            throw AnalyzerError.formatCreationFailed
        }

        // Input buffer for reading chunks from file
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: chunkSize
        ) else {
            throw AnalyzerError.formatCreationFailed
        }

        // Convert in chunks using input block pattern
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            do {
                // Read from file into input buffer
                try file.read(into: inputBuffer, frameCount: min(inNumPackets, self.chunkSize))

                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        if status == .error || error != nil {
            throw error ?? AnalyzerError.conversionFailed
        }

        return outputBuffer
    }

    /// For very large files, process in streaming fashion to avoid memory issues
    func extractFeaturesStreaming(
        from url: URL,
        extractor: FeatureExtractor,
        windowSize: AVAudioFrameCount = 44100  // 1 second windows at 44.1kHz
    ) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        var allFeatures: [[Float]] = []

        // Process file in windows
        while file.framePosition < file.length {
            let remainingFrames = AVAudioFrameCount(file.length - file.framePosition)
            let framesToRead = min(windowSize, remainingFrames)

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: framesToRead
            ) else { continue }

            try file.read(into: buffer, frameCount: framesToRead)
            let windowFeatures = try await extractor.extract(from: buffer)
            allFeatures.append(windowFeatures)
        }

        // Aggregate window features (mean pooling)
        return aggregateFeatures(allFeatures)
    }

    private func aggregateFeatures(_ windows: [[Float]]) -> [Float] {
        guard let first = windows.first else { return [] }
        var result = [Float](repeating: 0, count: first.count)

        for window in windows {
            for (i, value) in window.enumerated() {
                result[i] += value
            }
        }

        let count = Float(windows.count)
        return result.map { $0 / count }
    }
}

// PLAYBACK: Simple UI playback via AVAudioPlayer
@Observable class AudioPlayer {
    private var player: AVAudioPlayer?
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    func play(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        duration = player?.duration ?? 0
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }
}
```

---

## Feature Cache Design

### Compressed Storage in SwiftData

```swift
@Model class CachedFeatures {
    @Attribute(.unique) var audioHash: String
    var compressedFeatures: Data      // LZ4-compressed float32 bytes
    var pipelineVersion: String       // Full pipeline identifier (see below)
    var featureCount: Int
    var extractedAt: Date
}
```

### Cache Invalidation

The `pipelineVersion` string captures the complete feature pipeline state:

```swift
struct FeaturePipelineVersion: Codable, CustomStringConvertible {
    let extractorVersions: [String: String]  // e.g., ["spectral": "v2", "apple": "v1"]
    let windowingParams: WindowingParams
    let normalizationParams: NormalizationParams

    struct WindowingParams: Codable {
        let windowSize: Int           // e.g., 2048
        let hopSize: Int              // e.g., 512
        let fftSize: Int              // e.g., 2048
    }

    struct NormalizationParams: Codable {
        let method: String            // "zscore", "minmax", "none"
        let perFeature: Bool          // Whether normalization is per-feature or global
        let clipRange: ClosedRange<Float>?  // Optional clipping bounds
    }

    var description: String {
        // Generate deterministic hash for cache key
        let data = try! JSONEncoder().encode(self)
        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

extension CachedFeatures {
    /// Check if cached features are compatible with current pipeline
    func isCompatible(with pipeline: FeaturePipelineVersion) -> Bool {
        return self.pipelineVersion == pipeline.description
    }
}
```

Cache is invalidated when ANY of these change:
- `audioHash` — content hash of audio file
- Extractor versions — any extractor update
- Windowing parameters — FFT size, hop size, window size
- Normalization parameters — method, per-feature flag, clip range

### Compression Utilities

```swift
extension [Float] {
    func toCompressedData() -> Data {
        let bytes = withUnsafeBytes { Data($0) }
        return (try? bytes.compressed(using: .lz4)) ?? bytes
    }

    static func fromCompressedData(_ data: Data) -> [Float]? {
        guard let decompressed = try? data.decompressed(using: .lz4) else {
            return nil
        }
        return decompressed.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
    }
}
```

---

## File Access & Security-Scoped Bookmarks

Supports multiple music folders (local drives, external volumes, network shares):

```swift
@Observable class BookmarkManager {
    private let bookmarksKey = "musicFolderBookmarks"

    /// All registered music folder URLs with active access
    var musicFolderURLs: [URL] = []

    /// Track which URLs have active security scope access
    private var activeAccessURLs: Set<URL> = []

    // MARK: - Persistence

    /// Save bookmark for a folder, adding to existing bookmarks
    func addFolderAccess(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var bookmarks = loadBookmarkDictionary()
        bookmarks[url.path] = bookmark
        saveBookmarkDictionary(bookmarks)

        // Start access and track
        if url.startAccessingSecurityScopedResource() {
            activeAccessURLs.insert(url)
            if !musicFolderURLs.contains(url) {
                musicFolderURLs.append(url)
            }
        }
    }

    /// Remove a folder from bookmarks
    func removeFolderAccess(_ url: URL) {
        var bookmarks = loadBookmarkDictionary()
        bookmarks.removeValue(forKey: url.path)
        saveBookmarkDictionary(bookmarks)

        if activeAccessURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeAccessURLs.remove(url)
        }
        musicFolderURLs.removeAll { $0 == url }
    }

    // MARK: - Restoration

    /// Restore access to all saved bookmarks on app launch
    func restoreAllAccess() -> [URL: BookmarkRestoreResult] {
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
                    // Refresh stale bookmark
                    try addFolderAccess(url)
                    results[url] = .refreshed
                } else if url.startAccessingSecurityScopedResource() {
                    activeAccessURLs.insert(url)
                    musicFolderURLs.append(url)
                    results[url] = .restored
                } else {
                    results[url] = .accessDenied
                }
            } catch {
                // Bookmark is invalid (folder moved/deleted)
                if let url = URL(fileURLWithPath: path) as URL? {
                    results[url] = .invalid(error)
                }
            }
        }

        return results
    }

    enum BookmarkRestoreResult {
        case restored
        case refreshed
        case accessDenied
        case invalid(Error)
    }

    // MARK: - Access Control

    /// Check if we have access to a specific file URL
    func hasAccess(to fileURL: URL) -> Bool {
        musicFolderURLs.contains { folder in
            fileURL.path.hasPrefix(folder.path)
        }
    }

    /// Stop all security-scoped access (call on app terminate)
    func stopAllAccess() {
        for url in activeAccessURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeAccessURLs.removeAll()
    }

    // MARK: - Private

    private func loadBookmarkDictionary() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }

    private func saveBookmarkDictionary(_ bookmarks: [String: Data]) {
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }
}
```

**Usage in SetupWizard:**
```swift
struct FolderSelectionView: View {
    @Environment(BookmarkManager.self) var bookmarkManager

    var body: some View {
        VStack {
            ForEach(bookmarkManager.musicFolderURLs, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent)
                    Spacer()
                    Button("Remove") {
                        bookmarkManager.removeFolderAccess(url)
                    }
                }
            }

            Button("Add Music Folder") {
                // fileImporter handles security-scoped URL
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    try? bookmarkManager.addFolderAccess(url)
                }
            }
        }
    }
}
```

---

## Model Distribution & On-Demand Download

### Bundled with App (Phase 1)
- Baseline genre classifier (~5-10MB)
- Baseline timing classifier (~2-5MB)
- Baseline mood classifiers (~10-20MB total)
- Baseline descriptive classifiers (~10-20MB total)
- SpectralExtractor (code only)
- AppleSoundAnalysis (system framework)

**Base app size: ~80-100MB**

### On-Demand Download (Phase 2)

```swift
@Observable class ModelDownloadManager {
    enum DownloadableModel: String, CaseIterable {
        case whisperKit = "WhisperKit"      // ~150-400MB
        case panns = "PANNs"                 // ~150MB
        case clap = "CLAP"                   // ~200MB

        var displayName: String { rawValue }
        var sizeDescription: String {
            switch self {
            case .whisperKit: return "~300MB"
            case .panns: return "~150MB"
            case .clap: return "~200MB"
            }
        }

        /// Remote URLs for model and signature
        var modelURL: URL { URL(string: "https://models.cratebot.app/\(rawValue)/model.zip")! }
        var signatureURL: URL { URL(string: "https://models.cratebot.app/\(rawValue)/model.zip.sig")! }
        var checksumURL: URL { URL(string: "https://models.cratebot.app/\(rawValue)/SHA256SUMS")! }

        /// Local storage in Application Support (survives app updates)
        var localURL: URL {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CrateBot/Models/Downloaded/\(rawValue)")
        }

        var isDownloaded: Bool {
            FileManager.default.fileExists(atPath: localURL.appendingPathComponent("model.mlmodelc").path)
        }
    }

    var downloadProgress: [DownloadableModel: Double] = [:]
    var downloadErrors: [DownloadableModel: Error] = [:]

    /// Public key for signature verification (embedded in app)
    private let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
    -----END PUBLIC KEY-----
    """

    enum DownloadError: Error {
        case checksumMismatch(expected: String, actual: String)
        case signatureInvalid
        case signatureVerificationFailed(Error)
        case downloadFailed(Error)
        case extractionFailed
    }

    func download(_ model: DownloadableModel) async throws {
        downloadProgress[model] = 0

        // 1. Download model zip with progress
        let tempZipURL = try await downloadFile(from: model.modelURL, model: model)

        // 2. Download and verify checksum
        let checksumData = try await URLSession.shared.data(from: model.checksumURL).0
        let expectedChecksum = String(data: checksumData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actualChecksum = try sha256Hash(of: tempZipURL)

        guard expectedChecksum == actualChecksum else {
            throw DownloadError.checksumMismatch(expected: expectedChecksum, actual: actualChecksum)
        }

        // 3. Download and verify signature
        let signatureData = try await URLSession.shared.data(from: model.signatureURL).0
        try verifySignature(signatureData, for: tempZipURL)

        // 4. Extract to final location
        try FileManager.default.createDirectory(at: model.localURL, withIntermediateDirectories: true)
        try extractZip(tempZipURL, to: model.localURL)

        // 5. Cleanup temp file
        try? FileManager.default.removeItem(at: tempZipURL)

        downloadProgress[model] = 1.0
    }

    private func downloadFile(from url: URL, model: DownloadableModel) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: url, delegate: ProgressDelegate { progress in
            Task { @MainActor in
                self.downloadProgress[model] = progress * 0.8  // 80% for download
            }
        })
        return tempURL
    }

    private func sha256Hash(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func verifySignature(_ signature: Data, for fileURL: URL) throws {
        let fileData = try Data(contentsOf: fileURL)

        // Use Security framework for RSA signature verification
        guard let publicKey = SecKeyCreateWithData(
            publicKeyPEM.data(using: .utf8)! as CFData,
            [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary,
            nil
        ) else {
            throw DownloadError.signatureVerificationFailed(NSError(domain: "CrateBot", code: 1))
        }

        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            fileData as CFData,
            signature as CFData,
            &error
        )

        if let error = error?.takeRetainedValue() {
            throw DownloadError.signatureVerificationFailed(error)
        }

        guard isValid else {
            throw DownloadError.signatureInvalid
        }
    }

    func delete(_ model: DownloadableModel) throws {
        try FileManager.default.removeItem(at: model.localURL)
    }
}
```

**Security notes:**
- Models stored in `~/Library/Application Support/` (not inside app bundle)
- App updates via Sparkle won't overwrite downloaded models
- RSA signature verification prevents tampering with model blobs
- SHA256 checksum catches download corruption

**Full app with all models: ~500MB**

---

## External Integrations

### Vibe Generation (Anthropic API)

```swift
@Observable class AnthropicClient {
    private let rateLimiter = RateLimiter(requestsPerMinute: 50)
    private var apiKey: String? {
        try? Keychain.get("anthropic-api-key")
    }

    enum NetworkState {
        case online
        case offline
        case rateLimited(retryAfter: Date)
        case invalidKey
    }
    var state: NetworkState = .online

    func generateVibe(for track: Track) async throws -> String {
        guard let apiKey else {
            state = .invalidKey
            throw AnthropicError.noApiKey
        }

        guard NetworkMonitor.shared.isConnected else {
            state = .offline
            throw AnthropicError.offline
        }

        try await rateLimiter.acquire()

        let request = buildRequest(track: track, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            let retryAfter = Date.now.addingTimeInterval(60)
            state = .rateLimited(retryAfter: retryAfter)
            throw AnthropicError.rateLimited
        }

        return try decode(data)
    }

    func setApiKey(_ key: String) throws {
        try Keychain.set("anthropic-api-key", value: key)
    }

    func clearApiKey() throws {
        try Keychain.delete("anthropic-api-key")
    }
}
```

### Privacy Disclosure

```swift
struct PrivacyDisclosureView: View {
    var body: some View {
        GroupBox("Vibe Generation Privacy") {
            Text("When enabled, track metadata (title, artist, genre tags) is sent to Anthropic's API to generate creative descriptions.")
            Text("Audio files are never uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

### Hook Detection (WhisperKit)

- On-demand download (~150-400MB)
- CoreML-compiled Whisper
- Same accuracy as current faster-whisper
- Disabled in UI until model downloaded

### ID3 Tags

- ID3TagEditor Swift library
- Read/write TCON, TXXX, COMM frames
- Same tag structure as current Mutagen implementation

---

## Migration from Legacy Data

### Source: `~/.cratebot/`

```swift
@Observable class LegacyMigration {
    let legacyPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cratebot")

    enum MigrationState {
        case notNeeded
        case available
        case inProgress(Double)
        case completed(MigrationResult)
        case failed(Error)
    }

    struct MigrationResult {
        var tagOverridesImported: Int
        var lexiconImported: Bool
        var errors: [String]
    }

    var state: MigrationState = .notNeeded

    func checkAvailable() -> Bool {
        FileManager.default.fileExists(atPath: legacyPath.path)
    }

    func migrate(context: ModelContext) async throws -> MigrationResult {
        state = .inProgress(0)

        // 1. Create backup
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let backupPath = legacyPath.appendingPathExtension("backup-\(timestamp)")
        try FileManager.default.copyItem(at: legacyPath, to: backupPath)

        // 2. Detect schema version
        let version = try detectSchemaVersion()

        // 3. Import in transaction
        do {
            let overrides = try await importTagOverrides(
                version: version,
                context: context
            ) { progress in
                state = .inProgress(progress)
            }
            let lexicon = try importLexicon(version: version)

            let result = MigrationResult(
                tagOverridesImported: overrides,
                lexiconImported: lexicon,
                errors: []
            )
            state = .completed(result)
            return result
        } catch {
            // Rollback on failure
            try? rollback(from: backupPath)
            state = .failed(error)
            throw error
        }
    }

    private func rollback(from backup: URL) throws {
        if FileManager.default.fileExists(atPath: legacyPath.path) {
            try FileManager.default.removeItem(at: legacyPath)
        }
        try FileManager.default.moveItem(at: backup, to: legacyPath)
    }
}
```

---

## Data Storage

```
~/Library/Application Support/CrateBot/
├── Models/
│   ├── Bundled/
│   │   ├── GenreClassifier.mlmodelc
│   │   ├── TimingClassifier.mlmodelc
│   │   ├── MoodClassifiers/
│   │   └── DescriptiveClassifiers/
│   ├── UserTrained/
│   │   └── (same structure, user fine-tuned)
│   └── Downloaded/
│       ├── WhisperKit/
│       ├── PANNs/
│       └── CLAP/
├── CrateBot.store              # SwiftData
│   ├── CachedFeatures
│   └── TagOverrides
└── lexicon.json

Keychain: anthropic-api-key
UserDefaults: musicFolderBookmark, appSettings
```

### SwiftData Models

```swift
@Model class CachedFeatures {
    @Attribute(.unique) var audioHash: String
    var compressedFeatures: Data
    var pipelineVersion: String
    var featureCount: Int
    var extractedAt: Date

    init(
        audioHash: String,
        compressedFeatures: Data,
        pipelineVersion: String,
        featureCount: Int,
        extractedAt: Date = .now
    ) {
        self.audioHash = audioHash
        self.compressedFeatures = compressedFeatures
        self.pipelineVersion = pipelineVersion
        self.featureCount = featureCount
        self.extractedAt = extractedAt
    }
}

@Model class TagOverride {
    @Attribute(.unique) var audioHash: String
    var genre: String?
    var mood: [String]
    var timing: String?
    var descriptive: [String]
    var correctedAt: Date

    /// Required initializer with explicit defaults for array properties
    /// Prevents SwiftData migration issues when adding new array fields
    init(
        audioHash: String,
        genre: String? = nil,
        mood: [String] = [],          // Explicit empty array default
        timing: String? = nil,
        descriptive: [String] = [],   // Explicit empty array default
        correctedAt: Date = .now
    ) {
        self.audioHash = audioHash
        self.genre = genre
        self.mood = mood
        self.timing = timing
        self.descriptive = descriptive
        self.correctedAt = correctedAt
    }
}

// Schema versioning for migrations
enum CrateBotSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CachedFeatures.self, TagOverride.self]
    }
}

// Migration plan for future schema changes
enum CrateBotMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CrateBotSchemaV1.self]
    }
    static var stages: [MigrationStage] {
        []  // Add migration stages here when schema evolves
    }
}
```

---

## UI Components

| React (Current) | SwiftUI (New) |
|-----------------|---------------|
| SetupWizard.tsx | SetupWizard.swift |
| TaggingView.tsx | TaggingView.swift |
| TrainTab.tsx | TrainView.swift |
| RefineTab.tsx | RefineView.swift |
| SettingsPanel.tsx | SettingsView.swift |
| FileQueue.tsx | FileQueueView.swift |
| TagSelectionDialog.tsx | TagSelectionSheet.swift |
| AudioPlayer (wavesurfer) | WaveformView.swift (native Canvas) |

### Native Advantages
- Drag-drop: `onDrop(of:)` built-in
- File picker: `fileImporter()` native
- Progress: `ProgressView()` bound to async task
- Audio: `AVAudioPlayer` native playback
- Menu bar: native macOS integration
- Settings: native ⌘, window

---

## Project Structure

```
CrateBot/
├── CrateBot.xcodeproj
├── CrateBotCore/                    # Shared Swift Package
│   ├── Sources/
│   │   ├── Audio/
│   │   │   ├── AudioAnalyzer.swift
│   │   │   ├── AudioPlayer.swift
│   │   │   └── FeatureExtractors/
│   │   ├── ML/
│   │   │   ├── TagClassifier.swift
│   │   │   ├── MultiLabelPredictor.swift
│   │   │   └── ModelTrainer.swift
│   │   ├── Tags/
│   │   │   └── ID3TagEditor.swift
│   │   ├── Integrations/
│   │   │   ├── AnthropicClient.swift
│   │   │   └── WhisperKitWrapper.swift
│   │   ├── Data/
│   │   │   ├── BookmarkManager.swift
│   │   │   ├── FeatureCache.swift
│   │   │   └── LegacyMigration.swift
│   │   └── Networking/
│   │       ├── ModelDownloadManager.swift
│   │       └── NetworkMonitor.swift
│   └── Package.swift
├── CrateBot/                        # Main App
│   ├── App/
│   │   ├── CrateBotApp.swift
│   │   └── CrateBot.entitlements
│   ├── Views/
│   ├── ViewModels/
│   └── Resources/
├── CrateBotModelLab/                # Dev Tool App
│   ├── App/
│   ├── Views/
│   └── Resources/
└── Models/                          # Bundled CoreML models
```

---

## Build & Distribution

| Build | Expected Size |
|-------|---------------|
| CrateBot.app (base) | ~80-100MB |
| CrateBot.app (all models) | ~500MB |
| CrateBotModelLab.app | ~100-140MB |

### Distribution Method
- Direct .app download (notarized)
- DMG for sharing
- Sparkle 2.x for auto-updates
- Models hosted separately for on-demand download

### Sparkle + Sandbox Configuration

**Required entitlements for sandboxed Sparkle updates:**
```xml
<!-- Already included from sandbox -->
<key>com.apple.security.network.client</key>
<true/>

<!-- Required for Sparkle to write updates -->
<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
<array>
    <string>/</string>
</array>
```

**Alternative: XPC-based updates (recommended for strict sandbox):**
- Use Sparkle's XPC service architecture
- Update service runs outside sandbox
- Main app stays fully sandboxed

**Storage separation to prevent update conflicts:**

```
~/Library/Application Support/CrateBot/
├── Models/
│   ├── Downloaded/          # On-demand models (NOT affected by updates)
│   │   ├── WhisperKit/
│   │   ├── PANNs/
│   │   └── CLAP/
│   └── UserTrained/         # User's fine-tuned models (NOT affected)
├── CrateBot.store           # User data (NOT affected)
└── lexicon.json             # User customizations (NOT affected)

/Applications/CrateBot.app/
└── Contents/Resources/
    └── Models/Bundled/      # Baseline models (replaced on update)
```

**Update behavior:**
- App updates replace only the `.app` bundle
- Downloaded models in Application Support persist
- User-trained models persist
- SwiftData store persists
- User must re-download models only if bundled baseline models change significantly

---

## Key Benefits vs Current Architecture

| Aspect | Electron + Python | Native Swift |
|--------|-------------------|--------------|
| Runtimes | 2 (Electron + Python) | 1 (Swift) |
| Process coordination | HTTP + WebSocket | None needed |
| App size | 400MB+ | 80-100MB base |
| Startup time | 10-30s (server boot) | 1-2s |
| Memory | ~500MB+ | ~100-200MB |
| Stability | Process crashes, connection drops | Single process |
| Distribution | PyInstaller complexity | Standard .app |
| Notarization | Difficult | Standard |
| File access | Unrestricted | Sandboxed + bookmarks |

---

## Next Steps

1. Set up Xcode project with CrateBotCore package structure
2. Implement BookmarkManager and file access flow
3. Implement AudioAnalyzer with AVAudioEngine
4. Implement SpectralExtractor (MFCCs, spectral features)
5. Build Model Lab with subset sampling
6. Test feature combinations, determine optimal set
7. Train baseline models from your library
8. Implement binary classifier architecture for mood/descriptive
9. Build main CrateBot app with baseline models
10. Implement UI views
11. Add on-demand model download system
12. Add WhisperKit and Anthropic integrations
13. Migration tool for existing users
14. Distribution packaging and notarization
