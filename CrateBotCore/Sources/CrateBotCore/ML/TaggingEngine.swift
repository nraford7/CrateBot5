import Foundation
import AVFoundation
import os

/// Errors that can occur in the tagging engine
public enum TaggingEngineError: Error, LocalizedError {
    case modelDirectoryNotFound(String)
    case noModelsInDirectory(String)
    case analysisError(String)

    public var errorDescription: String? {
        switch self {
        case .modelDirectoryNotFound(let path):
            return "Model directory not found: \(path)"
        case .noModelsInDirectory(let path):
            return "No models found in directory: \(path)"
        case .analysisError(let reason):
            return "Analysis failed: \(reason)"
        }
    }
}

/// Stage 2 (judgment) argmax verdict: the highest-confidence Timing label
/// and its raw post-sigmoid Core ML probability. Surfaced on `TaggingResult`
/// so downstream callers (e.g., VibeGeneratorV2) can reason about Stage 2's
/// verdict without re-running inference. Nil when judgment did not run.
/// NOTE: Stage 2 outputs are NOT separately calibrated — only Stage 1 runs
/// through a `ConfidenceCalibrator`. Stage 2 was trained on Stage 1's
/// already-calibrated outputs, so its raw post-sigmoid value is the
/// honest signal. Do not apply a second calibration downstream.
public struct TimingPrediction: Sendable, Equatable {
    public let label: String
    public let confidence: Float

    public init(label: String, confidence: Float) {
        self.label = label
        self.confidence = confidence
    }
}

/// Result of analyzing a track with both user and Essentia classifiers
public struct TaggingResult: Sendable {
    /// User-trained classifier predictions (nil if no model loaded)
    public let userPredictions: UserTagPredictions?

    /// Essentia pre-trained predictions
    public let essentiaTags: EssentiaTags

    /// Raw EffNet embeddings (for debugging/analysis)
    public let embeddings: [Float]

    /// Raw genre activations from EffNet (400 classes)
    public let genreActivations: [Float]

    /// Whether Stage 2 (judgment) inference ran for this analysis.
    /// False when no paired judgment models are loaded or the input schema
    /// mismatched — relational (Timing) tags are then ABSENT, not stale.
    /// Defaults to false: without evidence of a judgment pass, the honest
    /// answer is "unavailable".
    public let judgmentAvailable: Bool

    /// Stage 2 argmax verdict — the highest-confidence Timing label and its
    /// raw post-sigmoid Core ML probability (Stage 2 is not separately
    /// calibrated; it was trained on Stage 1's calibrated outputs, so the
    /// raw post-sigmoid value IS the honest signal — do not double-calibrate).
    /// Populated when judgment fired (regardless of whether the label cleared
    /// its threshold and was emitted as a tag); nil when `judgmentAvailable`
    /// is false. Callers can apply their own confidence gate downstream
    /// (see VibeGeneratorV2's 0.5 mix-hint cutoff).
    public let timingPrediction: TimingPrediction?

    /// Per-tag Stage 1 binary classifier confidences (post-sigmoid, 0...1),
    /// raw — pre-booster, pre-threshold. Empty when no binary classifiers
    /// loaded. Surfaces so downstream consumers (vibe generator) can ground
    /// descriptions in audio-derived signal rather than thresholded labels.
    public let binaryConfidences: [String: Float]

    /// Per-group multi-class probabilities (BassType, VocalType, etc).
    /// Empty when no multi-class classifiers loaded.
    public let groupProbabilities: [String: [String: Float]]

    /// BPM read from the source file (TBPM frame or analyzer). Nil when the
    /// frame is absent or unreadable.
    public let bpm: Float?

    /// Track duration in seconds; 0 when the source duration is unavailable.
    public let durationSeconds: Float

    public init(
        userPredictions: UserTagPredictions? = nil,
        essentiaTags: EssentiaTags,
        embeddings: [Float],
        genreActivations: [Float],
        judgmentAvailable: Bool = false,
        timingPrediction: TimingPrediction? = nil,
        binaryConfidences: [String: Float] = [:],
        groupProbabilities: [String: [String: Float]] = [:],
        bpm: Float? = nil,
        durationSeconds: Float = 0
    ) {
        self.userPredictions = userPredictions
        self.essentiaTags = essentiaTags
        self.embeddings = embeddings
        self.genreActivations = genreActivations
        self.judgmentAvailable = judgmentAvailable
        self.timingPrediction = timingPrediction
        self.binaryConfidences = binaryConfidences
        self.groupProbabilities = groupProbabilities
        self.bpm = bpm
        self.durationSeconds = durationSeconds
    }
}

public struct UserTagPredictions: Sendable, Equatable {
    public let genre: String?
    public let timing: String?
    public let mood: String?

    // Structured descriptive output (new)
    public let bassType: String?          // From multi-class
    public let rhythm: [String]           // Binary predictions
    public let style: [String]            // Binary predictions
    public let vibes: [String]            // Binary predictions
    public let instruments: [String]      // Binary predictions
    public let vocalType: String?         // From multi-class
    public let acapella: Bool?            // Binary (separate classifier)
    public let customTags: [String]       // User-defined tags not in DescriptiveTagMapping

    // Legacy flat array (computed for backwards compatibility)
    public var descriptive: [String] {
        var result: [String] = []
        if let bass = bassType { result.append(bass) }
        result.append(contentsOf: rhythm)
        result.append(contentsOf: style)
        result.append(contentsOf: vibes)
        result.append(contentsOf: instruments)
        if let vocal = vocalType { result.append(vocal) }
        result.append(contentsOf: customTags)
        return result
    }

    // Convenience init with flat descriptive array (for backwards compat)
    public init(
        genre: String?,
        timing: String?,
        mood: String?,
        descriptive: [String]
    ) {
        self.genre = genre
        self.timing = timing
        self.mood = mood

        // Parse descriptive array into structured fields
        let organized = DescriptiveTagMapping.organize(descriptive)
        self.bassType = organized[.bassType]?.first
        self.rhythm = organized[.rhythm] ?? []
        self.style = organized[.style] ?? []
        self.vibes = organized[.vibes] ?? []
        self.instruments = organized[.instruments] ?? []
        self.vocalType = organized[.vocalType]?.first
        self.acapella = nil

        // Preserve tags not in DescriptiveTagMapping
        let knownTags = Set(organized.values.flatMap { $0 })
        self.customTags = descriptive.filter { !knownTags.contains($0) }
    }

    // Full structured init
    public init(
        genre: String?,
        timing: String?,
        mood: String?,
        bassType: String?,
        rhythm: [String],
        style: [String],
        vibes: [String],
        instruments: [String],
        vocalType: String?,
        acapella: Bool?,
        customTags: [String] = []
    ) {
        self.genre = genre
        self.timing = timing
        self.mood = mood
        self.bassType = bassType
        self.rhythm = rhythm
        self.style = style
        self.vibes = vibes
        self.instruments = instruments
        self.vocalType = vocalType
        self.acapella = acapella
        self.customTags = customTags
    }
}

/// Engine for analyzing audio with dual taxonomy (user + Essentia)
public actor TaggingEngine {
    /// Combined feature extractor (lazy-loaded when model is loaded)
    private var featureExtractor: CombinedFeatureExtractor?

    /// Fallback EffNet extractor for Essentia predictions when no user model loaded
    private var effnetExtractor: EffNetExtractor?

    private let essentiaClassifier: EssentiaClassifier
    private let audioAnalyzer: AudioAnalyzer
    private let logger = Logger(subsystem: "com.cratebot", category: "TaggingEngine")

    /// Feature extraction configuration (windowing). Must match the config the
    /// loaded model was trained with so inference and training share one path.
    private let featureExtractionConfig: FeatureExtractionConfig

    /// User-trained classifiers (one per tag)
    private var userClassifiers: [TagClassifier] = []

    /// Multi-class classifiers (one per tag group)
    private var multiClassClassifiers: [String: MultiClassClassifier] = [:]

    /// Stage 2 judgment classifiers (tag name → classifier). Loaded ONLY
    /// when metadata pairs them with the loaded Stage 1
    /// (`judgmentColumnNames` + `stage1ModelVersion`, written atomically by
    /// Phase B). Unpaired `_judgment` files are stale leftovers — refused.
    private var judgmentClassifiers: [String: TagClassifier] = [:]

    /// Stage 2 input schema (metadata.judgmentColumnNames) — set only when
    /// judgment classifiers loaded. Inference must reproduce these exact
    /// columns or skip judgment entirely.
    private var judgmentSchema: [String]?

    /// Category → pipeline-stage mapping (Timing → judgment)
    private let stageRegistry: TagStageRegistry

    /// Lowercased categories owned by Stage 2 (judgment)
    private let judgmentCategoriesLower: Set<String>

    /// ID3 reader for the inference-time BPM lookup (TBPM frame),
    /// mirroring Phase B's production BPM lookup in TrainingCoordinator.
    private let id3Manager = ID3Manager()

    /// Loaded model name
    private var loadedModelName: String?

    /// Loaded model metadata (for feature dimension detection)
    private var loadedMetadata: ModelMetadata?

    /// The Stage 1 model version string from loaded metadata. Used as the
    /// cache-invalidation half of the vibe cache key (the other half is the
    /// track path) — a Stage 1 model bump means stale vibes are no longer
    /// returned by `VibeCache`. Returns nil for empty strings so callers
    /// cannot accidentally bucket distinct models under `""`.
    public var stage1ModelVersion: String? {
        guard let version = loadedMetadata?.stage1ModelVersion, !version.isEmpty else {
            return nil
        }
        return version
    }

    /// Number of top predictions to keep for each category
    public var topPredictionCount: Int = 5

    /// Minimum probability threshold for Essentia predictions display
    public var predictionThreshold: Float = 0.2

    /// Global fallback classification threshold (uncategorized tags and the
    /// hybrid Essentia check). Per-category defaults + the strictness offset
    /// drive everything else — see `effectiveThreshold(forTag:)`.
    public var classificationThreshold: Float = 0.7

    /// Strictness offset applied ON TOP of per-category default thresholds
    /// (tuned per-tag thresholds still win). 0 = category defaults as-is.
    /// An offset — not an absolute threshold — so the category structure
    /// (Genre 0.7, Mood/Descriptive/Timing 0.55) survives every strictness level.
    private var strictnessOffset: Float = 0

    /// Per-tag threshold overrides (loaded from metadata or tag_thresholds.json)
    private var tagThresholds: [String: Float]?

    /// Lowercased tag name → lowercased category, built once at model load
    /// from metadata's `tags: [category: [tag]]` (for category threshold defaults)
    private var tagCategoryLookup: [String: String] = [:]

    /// Fallback mappings for tags without trained classifiers
    public var fallbackConfig: FallbackMappingConfig = FallbackMappingConfig()

    /// Confidence calibrator for adjusting raw classifier outputs
    private var confidenceCalibrator: ConfidenceCalibrator = ConfidenceCalibrator()

    /// Zero-shot matcher for CLAP-based tag predictions (no training needed)
    private let zeroShotMatcher: ZeroShotMatcher?

    /// Tag co-occurrence booster for post-hoc score adjustment
    private let cooccurrenceBooster: TagCooccurrenceBooster?

    /// Whether to apply co-occurrence boosting (set externally for A/B testing).
    /// Default OFF: Stage 2 subsumes co-occurrence boosting for judgment
    /// tags, and its Stage-1-only value is unproven pending eval.
    public var useCooccurrenceBoosting: Bool = false

    /// Minimum separation between a multi-class prediction and its runner-up.
    /// Below this margin the probability spread is too flat to force an answer.
    static let multiClassSeparationMargin: Float = 0.15

    public init(featureExtractionConfig: FeatureExtractionConfig = .default) throws {
        self.featureExtractionConfig = featureExtractionConfig
        let registry = TagStageRegistry()
        self.stageRegistry = registry
        self.judgmentCategoriesLower = Set(registry.categories(in: .judgment).map { $0.lowercased() })
        self.essentiaClassifier = try EssentiaClassifier()
        self.audioAnalyzer = AudioAnalyzer()
        self.zeroShotMatcher = ZeroShotMatcher.loadFromBundle()
        self.cooccurrenceBooster = TagCooccurrenceBooster.loadFromBundle()
        if cooccurrenceBooster != nil {
            logger.info("Loaded tag co-occurrence booster")
        }
        // Feature extractor is lazy-loaded when model is loaded
        // This allows matching the feature dimension to the trained model
    }

    /// Load all classifiers from a model directory
    /// - Parameters:
    ///   - modelDirectory: Directory containing .mlmodel files and metadata JSON
    ///   - modelName: Optional model name for locating metadata file (defaults to directory name)
    ///   - progress: Optional async callback for loading progress (0.0 to 1.0)
    ///   - featureConfig: Optional feature config override (defaults to auto-detection from metadata)
    /// - Returns: Number of classifiers loaded and the model name
    public func loadModel(
        from modelDirectory: URL,
        modelName: String? = nil,
        progress: ((Double) async -> Void)? = nil,
        featureConfig: CombinedFeatureExtractor.FeatureConfig? = nil
    ) async throws -> (classifierCount: Int, modelName: String) {
        let fileManager = FileManager.default

        // Find all .mlmodel files in the directory
        guard let contents = try? fileManager.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil) else {
            throw TaggingEngineError.modelDirectoryNotFound(modelDirectory.path)
        }

        let modelFiles = contents.filter { $0.pathExtension == "mlmodel" || $0.pathExtension == "mlmodelc" }

        guard !modelFiles.isEmpty else {
            throw TaggingEngineError.noModelsInDirectory(modelDirectory.path)
        }

        // Clear existing classifiers
        userClassifiers.removeAll()
        multiClassClassifiers.removeAll()
        judgmentClassifiers.removeAll()
        judgmentSchema = nil

        // Load metadata first to detect feature dimension
        // Use modelName.json if provided, otherwise fall back to metadata.json for legacy models
        let effectiveModelName = modelName ?? modelDirectory.lastPathComponent
        let metadataURL = modelDirectory.appendingPathComponent("\(effectiveModelName).json")
        var metadata = try? ModelMetadata.load(from: metadataURL)

        // Fall back to legacy metadata.json if model-named file not found
        if metadata == nil {
            let legacyMetadataURL = modelDirectory.appendingPathComponent("metadata.json")
            metadata = try? ModelMetadata.load(from: legacyMetadataURL)
        }
        loadedMetadata = metadata

        // Reject models trained on the pre-windowing (single-window) feature
        // pipeline: their classifiers expect single-shot embeddings and would
        // silently produce garbage against multi-window mean-pooled features.
        if let metadata = metadata {
            let currentHash = FeaturePipelineVersion.current(for: featureExtractionConfig).versionHash
            if metadata.pipelineVersion == FeaturePipelineVersion.legacySingleWindow.versionHash {
                logger.error("Model '\(effectiveModelName)' was trained on the pre-windowing feature pipeline (\(metadata.pipelineVersion)). Refusing to load — retrain with windowed extraction (expected \(currentHash)).")
                loadedMetadata = nil
                throw ModelManager.ModelError.incompatiblePipelineVersion(
                    expected: currentHash,
                    found: metadata.pipelineVersion
                )
            } else if metadata.pipelineVersion != currentHash {
                logger.warning("Model '\(effectiveModelName)' has unrecognized pipelineVersion '\(metadata.pipelineVersion)' (current: \(currentHash)). Loading anyway — predictions may be unreliable if features changed.")
            }
        } else {
            logger.error("Model '\(effectiveModelName)' has no readable metadata (\(metadataURL.lastPathComponent) or metadata.json missing/unparseable). Pipeline-version compatibility check SKIPPED — the model may have been trained on an incompatible feature pipeline and could produce unreliable predictions.")
        }

        // Build the lowercased tag → category reverse lookup once at model load
        // so threshold resolution can apply per-category defaults.
        // Indexed under BOTH the metadata tag name and its sanitized model-file
        // stem: binary classifiers are keyed by file stems, so multi-word tags
        // ("Late Night" → "Late_Night") would otherwise miss their category.
        // Sorted category keys + first-wins so a tag appearing in two categories
        // resolves deterministically (alphabetical category priority) — same
        // convention as ModelTrainer.trainModelsWithReport (ModelTrainer.swift:274-284).
        tagCategoryLookup = [:]
        if let metadata = metadata {
            for category in metadata.tags.keys.sorted() {
                let categoryLower = category.lowercased()
                for tag in metadata.tags[category] ?? [] {
                    for key in [tag.lowercased(), Self.sanitizeModelFileName(tag).lowercased()]
                    where tagCategoryLookup[key] == nil {
                        tagCategoryLookup[key] = categoryLower
                    }
                }
            }
        }

        // Load per-tag thresholds from metadata first, then override with file
        tagThresholds = metadata?.tagThresholds
        let thresholdsFileURL = modelDirectory.appendingPathComponent("tag_thresholds.json")
        if let thresholdsData = try? Data(contentsOf: thresholdsFileURL),
           let json = try? JSONSerialization.jsonObject(with: thresholdsData) as? [String: Any] {
            // Extract thresholds from nested format: {"tags": {"TagName": {"threshold": 0.82}}}
            // or flat format: {"TagName": 0.82}
            var fileThresholds: [String: Float] = [:]
            if let tagsDict = json["tags"] as? [String: Any] {
                for (tag, value) in tagsDict {
                    if let info = value as? [String: Any], let thresh = info["threshold"] as? Double {
                        fileThresholds[tag] = Float(thresh)
                    } else if let thresh = value as? Double {
                        fileThresholds[tag] = Float(thresh)
                    }
                }
            } else {
                // Try flat format
                for (tag, value) in json {
                    if let thresh = value as? Double {
                        fileThresholds[tag] = Float(thresh)
                    }
                }
            }

            if !fileThresholds.isEmpty {
                if tagThresholds != nil {
                    tagThresholds!.merge(fileThresholds) { _, new in new }
                } else {
                    tagThresholds = fileThresholds
                }
                logger.info("Loaded per-tag thresholds from tag_thresholds.json (\(fileThresholds.count) entries)")
            }
        }

        // Index tuned thresholds under their sanitized model-file stems too:
        // binary classifiers look up by file stem ("Late_Night"), while
        // tag_thresholds.json keys are metadata tag names ("Late Night").
        if let thresholds = tagThresholds {
            tagThresholds = Self.addingSanitizedStemAliases(thresholds)
        }

        // Detect feature config from metadata if not provided
        let effectiveConfig: CombinedFeatureExtractor.FeatureConfig
        if let config = featureConfig {
            effectiveConfig = config
        } else if let metadata = metadata {
            switch metadata.featureDimension {
            case 1280: effectiveConfig = .effnetOnly
            case 1680: effectiveConfig = .effnetPlusGenres
            case 2960: effectiveConfig = .effnetGenresCLAPMAEST
            default: effectiveConfig = .effnetGenresCLAP
            }
            logger.info("Detected feature dimension \(metadata.featureDimension), using \(effectiveConfig.description)")
        } else {
            // Default to EffNet+Genres for models without metadata
            effectiveConfig = .effnetPlusGenres
            logger.info("No metadata found, defaulting to \(effectiveConfig.description)")
        }

        // Initialize the combined feature extractor with the appropriate config
        featureExtractor = try CombinedFeatureExtractor(config: effectiveConfig)

        // A degraded extractor (e.g. CLAP/MAEST model missing) produces fewer dimensions
        // than the model was trained on; predictions would silently fail per-tag. Refuse.
        if let metadata = metadata {
            let actualDimension = await featureExtractor!.featureDimension
            if actualDimension != metadata.featureDimension {
                throw ModelManager.ModelError.incompatiblePipelineVersion(
                    expected: "\(metadata.featureDimension)-dim features",
                    found: "\(actualDimension)-dim extractor (a feature model may have failed to load)"
                )
            }
        }

        // Load confidence calibrator if temperature is stored in metadata
        if let metadata = metadata, let temp = metadata.calibratorTemperature {
            confidenceCalibrator = ConfidenceCalibrator(temperature: temp, smoothingFactor: 0.1)
            logger.info("Loaded confidence calibrator with temperature: \(temp)")
        } else {
            // Reset to default calibrator if no temperature stored
            confidenceCalibrator = ConfidenceCalibrator()
        }

        // Filter out multi-class (_multiclass) and Stage 2 judgment
        // (_judgment) model files: judgment models take JudgmentFeatureVector
        // columns, not audio features — loading one as a binary classifier
        // would silently misfire. (Chunk 4 adds the actual judgment loading.)
        let binaryModelFiles = modelFiles.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            return !name.hasSuffix("_multiclass") && !name.hasSuffix("_judgment")
        }

        let totalFiles = binaryModelFiles.count

        // Load each binary classifier
        for (index, modelURL) in binaryModelFiles.enumerated() {
            let tagName = modelURL.deletingPathExtension().lastPathComponent
            do {
                let classifier = try TagClassifier(tagName: tagName, modelURL: modelURL, threshold: 0.5)
                userClassifiers.append(classifier)
            } catch {
                logger.warning("Failed to load classifier for '\(tagName)': \(error.localizedDescription)")
            }

            // Report progress and yield to allow UI updates
            await progress?(Double(index + 1) / Double(totalFiles))
            await Task.yield()
        }

        // Load multi-class classifiers from metadata
        if let metadata = metadata {
            for groupInfo in metadata.tagGroups {
                // Try both compiled and uncompiled model paths
                let modelURLs = [
                    modelDirectory.appendingPathComponent("\(groupInfo.groupName)_multiclass.mlmodelc"),
                    modelDirectory.appendingPathComponent("\(groupInfo.groupName)_multiclass.mlmodel")
                ]

                guard let modelURL = modelURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
                    logger.warning("Multi-class model not found for group '\(groupInfo.groupName)'")
                    continue
                }

                do {
                    let classifier = try MultiClassClassifier(
                        groupName: groupInfo.groupName,
                        classes: groupInfo.classes,
                        modelURL: modelURL,
                        featureCount: metadata.featureDimension
                    )
                    multiClassClassifiers[groupInfo.groupName] = classifier
                    logger.info("Loaded multi-class classifier: \(groupInfo.groupName)")
                } catch {
                    logger.error("Failed to load multi-class '\(groupInfo.groupName)': \(error.localizedDescription)")
                }
            }
        }

        // Load Stage 2 judgment classifiers — ONLY when metadata pairs them
        // with this Stage 1. `judgmentColumnNames` and `stage1ModelVersion`
        // are written atomically by Phase B against the exact Stage 1 model
        // set in this directory, so their joint presence IS the pairing.
        // Missing either one means the `_judgment` files predate the current
        // Stage 1 (or judgment training never completed): loading them would
        // produce stale judgments from mismatched inputs. Refuse.
        let judgmentModelFiles = modelFiles.filter {
            $0.deletingPathExtension().lastPathComponent.hasSuffix("_judgment")
        }
        if !judgmentModelFiles.isEmpty {
            if let metadata = metadata,
               let columnNames = metadata.judgmentColumnNames,
               metadata.stage1ModelVersion != nil {
                // Training writes `sanitizeFileName(tag)_judgment.mlmodel`;
                // map sanitized file names back to the original tag names
                // via the metadata category map (judgment-stage categories).
                var fileNameToTag: [String: String] = [:]
                for (category, categoryTags) in metadata.tags
                where judgmentCategoriesLower.contains(category.lowercased()) {
                    for tag in categoryTags {
                        fileNameToTag[Self.sanitizeModelFileName(tag)] = tag
                    }
                }

                for modelURL in judgmentModelFiles {
                    let fileName = modelURL.deletingPathExtension().lastPathComponent
                    let baseName = String(fileName.dropLast("_judgment".count))
                    let tagName = fileNameToTag[baseName] ?? baseName
                    do {
                        // Threshold 0.5 is a placeholder — judgment decisions
                        // use effectiveThreshold(forTag:) (Timing default 0.55).
                        judgmentClassifiers[tagName] = try TagClassifier(
                            tagName: tagName, modelURL: modelURL, threshold: 0.5)
                    } catch {
                        logger.warning("Failed to load judgment classifier '\(tagName)': \(error.localizedDescription)")
                    }
                }

                if !judgmentClassifiers.isEmpty {
                    judgmentSchema = columnNames
                    logger.info("Loaded \(self.judgmentClassifiers.count) Stage 2 judgment classifiers (schema: \(columnNames.count) columns)")
                }
            } else {
                logger.warning("\(judgmentModelFiles.count) _judgment model files present but metadata does not pair them (judgmentColumnNames: \(metadata?.judgmentColumnNames != nil), stage1ModelVersion: \(metadata?.stage1ModelVersion != nil)) — Stage 2 disabled, no stale judgments")
            }
        }

        // With Stage 2 active, tuned thresholds for judgment-stage (Timing)
        // tags are stale: they were optimized on legacy Stage-1 scores and
        // would silently gate the new judgment confidences. Drop them —
        // `--optimize` rewrites them on final pipeline scores post-retrain.
        if !judgmentClassifiers.isEmpty, let thresholds = tagThresholds {
            let stale = thresholds.keys.filter { key in
                guard let category = tagCategoryLookup[key.lowercased()] else { return false }
                return judgmentCategoriesLower.contains(category)
            }.sorted()
            if !stale.isEmpty {
                tagThresholds = thresholds.filter { !stale.contains($0.key) }
                logger.info("Dropped \(stale.count) stale tuned Timing threshold(s) (optimized on legacy Stage-1 scores; Stage 2 judgment now owns these tags): \(stale.joined(separator: ", "))")
            }
        }

        // Use provided model name, or fall back to directory name
        let resolvedModelName = modelName ?? modelDirectory.lastPathComponent
        loadedModelName = resolvedModelName

        return (userClassifiers.count + multiClassClassifiers.count + judgmentClassifiers.count, resolvedModelName)
    }

    /// Mirror of ModelTrainer.sanitizeFileName — the transform applied to a
    /// tag name when its `_judgment` model file is written.
    private static func sanitizeModelFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Add a `sanitizeModelFileName(key)` alias for every tuned threshold so
    /// stem-keyed lookups (binary classifiers) resolve. Sorted keys +
    /// first-wins keeps alias collisions deterministic; explicit keys are
    /// never overwritten.
    private static func addingSanitizedStemAliases(_ thresholds: [String: Float]) -> [String: Float] {
        var result = thresholds
        for key in thresholds.keys.sorted() {
            let alias = sanitizeModelFileName(key)
            if alias != key, result[alias] == nil {
                result[alias] = thresholds[key]
            }
        }
        return result
    }

    /// Load user-trained model (legacy single-classifier support)
    public func loadUserModel(from url: URL) throws {
        let tagName = url.deletingPathExtension().lastPathComponent
        let classifier = try TagClassifier(tagName: tagName, modelURL: url, threshold: 0.5)
        userClassifiers = [classifier]
        loadedModelName = tagName
    }

    /// Unload all user models
    public func unloadUserModel() {
        userClassifiers.removeAll()
        multiClassClassifiers.removeAll()
        judgmentClassifiers.removeAll()
        judgmentSchema = nil
        loadedModelName = nil
        loadedMetadata = nil
        featureExtractor = nil
        tagCategoryLookup = [:]
    }

    /// Check if user model is loaded
    public var hasUserModel: Bool {
        !userClassifiers.isEmpty || !multiClassClassifiers.isEmpty
    }

    /// Get loaded model name
    public var currentModelName: String? {
        loadedModelName
    }

    /// Get list of loaded tag classifiers
    public var loadedTags: [String] {
        userClassifiers.map { $0.tagName }
    }

    /// Tags with a loaded Stage 2 judgment classifier (sorted)
    public var loadedJudgmentTags: [String] {
        judgmentClassifiers.keys.sorted()
    }

    /// Get list of tags available via fallback mappings
    public var fallbackTags: [String] {
        fallbackConfig.enabled ? fallbackConfig.mappings.map { $0.userTag } : []
    }

    /// Update fallback mapping configuration
    public func setFallbackConfig(_ config: FallbackMappingConfig) {
        self.fallbackConfig = config
    }

    /// Update the strictness offset (from the app's strictness setting).
    /// The offset shifts every per-category default threshold up or down;
    /// tuned per-tag thresholds still win.
    public func setStrictnessOffset(_ offset: Float) {
        self.strictnessOffset = offset
    }

    /// Deprecated shim: legacy callers passed an absolute threshold, which
    /// flattened the per-category defaults into one number. Map it to an
    /// offset relative to the 0.7 base so unknown callers degrade sanely.
    @available(*, deprecated, message: "Use setStrictnessOffset(_:) — absolute thresholds flatten per-category defaults")
    public func setClassificationThreshold(_ threshold: Float) {
        setStrictnessOffset(threshold - 0.7)
    }

    /// Default classification threshold for a tag category, used when no tuned
    /// per-tag threshold exists (the strictness offset is applied on top).
    func defaultThreshold(forCategory category: String?) -> Float {
        switch category?.lowercased() {
        case "genre": return 0.7
        case "mood", "descriptive", "timing": return 0.55
        default: return classificationThreshold // unknown/uncategorized: global fallback (0.7 default)
        }
    }

    /// Resolve the classification threshold for a tag.
    /// Precedence: tuned `tagThresholds` (tag name or sanitized stem — both
    /// indexed at load) → category default + strictness offset, clamped to
    /// [0.05, 0.99].
    func effectiveThreshold(forTag tag: String) -> Float {
        if let tuned = tagThresholds?[tag] { return tuned }
        let base = defaultThreshold(forCategory: tagCategoryLookup[tag.lowercased()])
        return min(max(base + strictnessOffset, 0.05), 0.99)
    }

    /// Analyze audio file and return dual taxonomy predictions
    public func analyze(url: URL) async throws -> TaggingResult {
        // Snapshot Stage 2 state BEFORE any suspension point: the awaits below
        // (feature extraction, BPM read) are actor reentrancy windows where a
        // concurrent loadModel could swap judgmentClassifiers/judgmentSchema
        // mid-analysis. Judgment must run against the state this pass started with.
        let judgmentSnapshot = JudgmentSnapshot(
            classifiers: judgmentClassifiers, schema: judgmentSchema)

        // Load audio at 16kHz
        let buffer = try await audioAnalyzer.loadAudio(from: url, targetSampleRate: EffNetExtractor.targetSampleRate)

        // Extract features using combined extractor if available, otherwise use fallback
        let extendedFeatures: [Float]
        let embeddings: [Float]
        let genreActivations: [Float]

        if let extractor = featureExtractor {
            // Use combined extractor with multi-window mean pooling — the same
            // extraction path TrainingDataCollector uses, so features at
            // inference match the features the model was trained on.
            extendedFeatures = try await extractor.extractWindowed(
                from: buffer, config: featureExtractionConfig)

            // For Essentia predictions, we still need the raw embeddings and genre activations
            // These are always the first 1280 and next 400 dimensions respectively
            if extendedFeatures.count >= 1680 {
                embeddings = Array(extendedFeatures.prefix(1280))
                genreActivations = Array(extendedFeatures.dropFirst(1280).prefix(400))
            } else if extendedFeatures.count == 1280 {
                embeddings = extendedFeatures
                genreActivations = []
            } else {
                embeddings = []
                genreActivations = []
            }
        } else {
            // No model loaded - use fallback EffNet extractor for Essentia predictions only
            let fallbackExtractor = try getOrCreateEffNetExtractor()
            let (emb, genres) = try await fallbackExtractor.extractWithGenres(from: buffer)
            embeddings = emb
            genreActivations = genres
            extendedFeatures = embeddings + genreActivations
        }

        // Get Essentia predictions
        let moodPredictions = try await essentiaClassifier.predictMoodTheme(embeddings: embeddings)
        let instrumentPredictions = try await essentiaClassifier.predictInstruments(embeddings: embeddings)
        let genrePredictions = essentiaClassifier.labelGenres(activations: genreActivations)

        // Get top predictions
        let topMoods = essentiaClassifier.topPredictions(moodPredictions, count: topPredictionCount, threshold: predictionThreshold)
        let topInstruments = essentiaClassifier.topPredictions(instrumentPredictions, count: topPredictionCount, threshold: predictionThreshold)
        let topGenres = essentiaClassifier.topPredictions(genrePredictions, count: topPredictionCount, threshold: predictionThreshold)

        let essentiaTags = EssentiaTags(
            genres: topGenres.map { $0.tag },
            moods: topMoods.map { $0.tag },
            instruments: topInstruments.map { $0.tag }
        )

        // Get user predictions from trained classifiers with hybrid Essentia fallback
        var predictedTags: [String] = []
        var trainedTagNames = Set<String>()

        // Pass 1: collect calibrated raw probabilities for all classifiers
        var rawProbabilities: [String: Float] = [:]
        for classifier in userClassifiers {
            trainedTagNames.insert(classifier.tagName.lowercased())
            do {
                let (_, rawConfidence) = try classifier.predictWithConfidence(features: extendedFeatures)
                let calibrated = confidenceCalibrator.calibrate(rawConfidence)
                rawProbabilities[classifier.tagName] = calibrated
            } catch {
                logger.error("Classifier '\(classifier.tagName)' failed: \(error.localizedDescription)")
            }
        }

        // Pass 2: apply co-occurrence boosting if enabled.
        // The booster only ever sees perception-stage probabilities —
        // Stage 2 subsumes its role for judgment (Timing) tags.
        let adjustedProbabilities: [String: Float]
        if useCooccurrenceBoosting, let booster = cooccurrenceBooster {
            adjustedProbabilities = booster.adjust(
                probabilities: boosterInputProbabilities(rawProbabilities))
        } else {
            adjustedProbabilities = rawProbabilities
        }

        // Pass 3: threshold and apply perception tags (judgment-stage tags
        // are never emitted here — they belong to Stage 2)
        predictedTags.append(contentsOf: binaryThresholdPass(
            rawProbabilities: rawProbabilities,
            adjustedProbabilities: adjustedProbabilities,
            moodPredictions: moodPredictions,
            genrePredictions: genrePredictions,
            instrumentPredictions: instrumentPredictions
        ))

        // Run multi-class predictions (with confidence + separation gate);
        // collect each group's full distribution for Stage 2.
        var groupProbabilities: [String: [String: Float]] = [:]

        for (groupName, classifier) in multiClassClassifiers {
            do {
                let prediction = try await classifier.predict(features: extendedFeatures)
                groupProbabilities[groupName] = prediction.classProbabilities
                if multiClassEmits(prediction) {
                    predictedTags.append(prediction.predictedClass)
                }
                // Track all classes from this group as trained tags (to avoid fallback duplicates)
                for className in classifier.classes {
                    trainedTagNames.insert(className.lowercased())
                }
            } catch {
                logger.error("Multi-class prediction failed: \(error.localizedDescription)")
            }
        }

        // Hoisted from the judgment branch so the vibe generator can read
        // BPM/duration even when Stage 2 does not fire. `judgmentPass` takes
        // `Float?` for duration; the `TaggingResult` field coerces nil → 0.
        let bpm = await readBPM(from: url)
        let durationOptional = readDurationSeconds(from: url)

        // Pass 4 (judgment): Stage 2 owns Timing tags. Inputs are the pass-1
        // calibrated PRE-BOOST probabilities + multi-class distributions +
        // BPM + duration — exactly the rows JudgmentDataGenerator trained on.
        let judgmentAvailable: Bool
        let timingPrediction: TimingPrediction?
        if !judgmentSnapshot.classifiers.isEmpty {
            for tagName in judgmentSnapshot.classifiers.keys {
                trainedTagNames.insert(tagName.lowercased())
            }
            let judgment = judgmentPass(
                snapshot: judgmentSnapshot,
                binaryConfidences: rawProbabilities,
                groupProbabilities: groupProbabilities,
                bpm: bpm,
                durationSeconds: durationOptional
            )
            predictedTags.append(contentsOf: judgment.tags)
            judgmentAvailable = judgment.judgmentAvailable
            timingPrediction = judgment.timingPrediction
        } else {
            judgmentAvailable = false
            timingPrediction = nil
        }

        // Zero-shot CLAP predictions for tags without trained classifiers
        // (judgment-stage tags excluded — Stage 2's exclusive domain)
        if let matcher = zeroShotMatcher, extendedFeatures.count >= 2192 {
            let clapEmbedding = Array(extendedFeatures[1680..<2192])
            let zeroShotMatches = matcher.match(
                audioEmbedding: clapEmbedding,
                threshold: 0.3,
                maxResults: 3,
                excludingTags: trainedTagNames
            )
            predictedTags.append(
                contentsOf: zeroShotPerceptionFilter(zeroShotMatches.map { $0.tag }))
        }

        // Apply fallback mappings for tags without trained classifiers
        if fallbackConfig.enabled {
            let fallbackPredictions = applyFallbackMappings(
                moodPredictions: moodPredictions,
                genrePredictions: genrePredictions,
                instrumentPredictions: instrumentPredictions,
                excludingTrained: trainedTagNames
            )
            predictedTags.append(contentsOf: fallbackPredictions)
        }

        // Acapella sanity gate: a track is only an acapella when it carries
        // vocals AND no instrumentation. If Essentia detected any instruments
        // (vocal classifiers excluded), drop "Acapella" from the predicted
        // set so it cannot win the Genre slot. This is a precision floor — a
        // misfire here is more visible to the user than a missed acapella.
        let essentiaInstrumentSignals = essentiaTags.instruments.filter { name in
            let lower = name.lowercased()
            return !lower.contains("voice") && !lower.contains("vocal") && !lower.contains("acapella")
        }
        if !essentiaInstrumentSignals.isEmpty {
            predictedTags.removeAll { $0.lowercased() == "acapella" }
        }

        // Categorize predicted tags using model metadata
        let userPredictions: UserTagPredictions? = predictedTags.isEmpty ? nil : categorizePredictions(predictedTags)

        return TaggingResult(
            userPredictions: userPredictions,
            essentiaTags: essentiaTags,
            embeddings: embeddings,
            genreActivations: genreActivations,
            judgmentAvailable: judgmentAvailable,
            timingPrediction: timingPrediction,
            binaryConfidences: rawProbabilities,
            groupProbabilities: groupProbabilities,
            bpm: bpm,
            durationSeconds: durationOptional ?? 0
        )
    }

    // MARK: - Stage partition + decision passes

    /// True when the tag's metadata category is owned by Stage 2 (judgment).
    /// Uncategorized tags default to perception — Stage 2 only ever handles
    /// tags it was explicitly trained for.
    private func isJudgmentStageTag(_ tag: String) -> Bool {
        guard let category = tagCategoryLookup[tag.lowercased()] else { return false }
        return judgmentCategoriesLower.contains(category)
    }

    /// Booster scope: filter to perception-stage tags. Judgment tags never
    /// reach the co-occurrence booster — Stage 2 subsumes it for them.
    func boosterInputProbabilities(_ probabilities: [String: Float]) -> [String: Float] {
        probabilities.filter { !isJudgmentStageTag($0.key) }
    }

    /// Pass 3: threshold the (possibly boosted) probabilities into emitted
    /// tags, with the hybrid Essentia fallback on raw (pre-boost) confidence.
    /// Judgment-stage tags are NEVER emitted by this pass.
    func binaryThresholdPass(
        rawProbabilities: [String: Float],
        adjustedProbabilities: [String: Float],
        moodPredictions: [String: Float],
        genrePredictions: [String: Float],
        instrumentPredictions: [String: Float]
    ) -> [String] {
        var emitted: [String] = []
        for (tagName, confidence) in adjustedProbabilities {
            if isJudgmentStageTag(tagName) { continue }
            let threshold = effectiveThreshold(forTag: tagName)
            if confidence >= threshold {
                // (Possibly boosted) confidence meets threshold - apply tag
                emitted.append(tagName)
            } else {
                let raw = rawProbabilities[tagName, default: 0]
                if raw > 0 {
                    // Below threshold but non-zero - try hybrid Essentia check
                    // Use raw (pre-boost) confidence to maintain original fallback semantics
                    let shouldApply = checkHybridEssentiaFallback(
                        tagName: tagName,
                        userConfidence: raw,
                        moodPredictions: moodPredictions,
                        genrePredictions: genrePredictions,
                        instrumentPredictions: instrumentPredictions
                    )
                    if shouldApply {
                        emitted.append(tagName)
                    }
                }
            }
        }
        return emitted
    }

    /// Multi-class gate: the predicted class must clear its threshold AND
    /// beat the runner-up by `multiClassSeparationMargin` — a flat spread
    /// never forces an answer.
    func multiClassGatePasses(_ prediction: MultiClassClassifier.Prediction) -> Bool {
        let threshold = effectiveThreshold(forTag: prediction.predictedClass)
        return prediction.confidence >= threshold
            && prediction.confidence - prediction.runnerUpConfidence >= Self.multiClassSeparationMargin
    }

    /// Multi-class emission guard: the gate must pass AND the winning class
    /// must not be a judgment-stage tag — a group like Energy can contain a
    /// Timing class ("Peak") that only Stage 2 may emit.
    func multiClassEmits(_ prediction: MultiClassClassifier.Prediction) -> Bool {
        multiClassGatePasses(prediction) && !isJudgmentStageTag(prediction.predictedClass)
    }

    /// Zero-shot pass partition: judgment-stage tags never come from CLAP
    /// zero-shot — Stage 2's exclusive domain (same partition as the other passes).
    func zeroShotPerceptionFilter(_ tags: [String]) -> [String] {
        tags.filter { !isJudgmentStageTag($0) }
    }

    /// Immutable snapshot of Stage 2 state, captured at the start of an
    /// analyze pass so actor reentrancy (a concurrent loadModel during an
    /// await) cannot swap the classifier/schema pairing mid-analysis.
    struct JudgmentSnapshot {
        let classifiers: [String: TagClassifier]
        let schema: [String]?
    }

    /// Pass 4: Stage 2 judgment inference.
    ///
    /// Builds the JudgmentFeatureVector from Stage 1 outputs and validates
    /// its columns against the schema the judgment models were trained on
    /// (metadata.judgmentColumnNames). Any mismatch — a failed Stage 1
    /// classifier, a missing group, an extra column — skips judgment with a
    /// logged error: NEVER garbage predictions from misaligned inputs.
    ///
    /// - Returns: emitted judgment tags, and whether judgment actually ran.
    func judgmentPass(
        binaryConfidences: [String: Float],
        groupProbabilities: [String: [String: Float]],
        bpm: Float?,
        durationSeconds: Float?
    ) -> (tags: [String], judgmentAvailable: Bool, timingPrediction: TimingPrediction?) {
        judgmentPass(
            snapshot: JudgmentSnapshot(classifiers: judgmentClassifiers, schema: judgmentSchema),
            binaryConfidences: binaryConfidences,
            groupProbabilities: groupProbabilities,
            bpm: bpm,
            durationSeconds: durationSeconds
        )
    }

    /// Snapshot-based judgment pass: `analyze` captures the snapshot before
    /// its first await so reentrant loadModel calls cannot swap the
    /// classifier/schema pairing between Stage 1 and Stage 2.
    ///
    /// In addition to the emitted tags (thresholded) and the availability
    /// flag, the pass returns `timingPrediction` — the argmax (label, raw
    /// post-sigmoid Core ML probability) across all judgment classifiers
    /// that successfully ran. Nil when judgment did not run or every
    /// classifier threw. Stage 2 is NOT separately calibrated (it was
    /// trained on Stage 1's calibrated outputs), so the raw post-sigmoid
    /// value is the honest signal — downstream callers can apply their
    /// own gate (see VibeGeneratorV2's 0.5 mix-hint cutoff) without
    /// double-calibrating.
    func judgmentPass(
        snapshot: JudgmentSnapshot,
        binaryConfidences: [String: Float],
        groupProbabilities: [String: [String: Float]],
        bpm: Float?,
        durationSeconds: Float?
    ) -> (tags: [String], judgmentAvailable: Bool, timingPrediction: TimingPrediction?) {
        guard !snapshot.classifiers.isEmpty, let schema = snapshot.schema else {
            return ([], false, nil)
        }

        let vector = JudgmentFeatureVector(
            binaryConfidences: binaryConfidences,
            groupProbabilities: groupProbabilities,
            bpm: bpm,
            durationSeconds: durationSeconds
        )
        guard vector.columnNames == schema else {
            logger.error("Stage 2 schema mismatch: built \(vector.columnNames.count) columns but the judgment models expect \(schema.count) (metadata.judgmentColumnNames) — judgment skipped, relational tags unavailable")
            return ([], false, nil)
        }

        let namedFeatures = Dictionary(uniqueKeysWithValues: zip(vector.columnNames, vector.values))
        var emitted: [String] = []
        var argmax: TimingPrediction?
        for (tagName, classifier) in snapshot.classifiers.sorted(by: { $0.key < $1.key }) {
            do {
                let (_, confidence) = try classifier.predictWithConfidence(namedFeatures: namedFeatures)
                if confidence >= effectiveThreshold(forTag: tagName) {
                    emitted.append(tagName)
                }
                // Tie-break: strict `>` combined with the sorted iteration above means
                // exact-confidence ties resolve to the alphabetically-first tag name
                // (the incumbent wins). Deterministic; documented so future maintainers
                // don't reorder iteration without thinking about argmax stability.
                if argmax == nil || confidence > argmax!.confidence {
                    argmax = TimingPrediction(label: tagName, confidence: confidence)
                }
            } catch {
                logger.error("Judgment classifier '\(tagName)' failed: \(error.localizedDescription)")
            }
        }
        return (emitted, true, argmax)
    }

    /// Inference-time BPM: the ID3 TBPM frame, mirroring Phase B's
    /// production BPM lookup. nil (→ sentinel -1.0) when absent/invalid.
    private func readBPM(from url: URL) async -> Float? {
        guard let tags = try? await id3Manager.readTags(from: url),
              let bpmString = tags.bpm,
              let bpm = Float(bpmString.trimmingCharacters(in: .whitespaces)),
              bpm > 0 else {
            return nil
        }
        return bpm
    }

    /// Inference-time duration in seconds from the audio file header
    /// (`AVAudioFile.length / processingFormat.sampleRate`) — a header
    /// read, no decode. Mirrors Phase B's production duration lookup.
    private func readDurationSeconds(from url: URL) -> Float? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return Float(Double(file.length) / sampleRate)
    }

    /// Analyze audio buffer directly (for cases where buffer is already loaded)
    public func analyze(buffer: AVAudioPCMBuffer) async throws -> TaggingResult {
        // Use fallback EffNet extractor for Essentia predictions
        let fallbackExtractor = try getOrCreateEffNetExtractor()
        let (embeddings, genreActivations) = try await fallbackExtractor.extractWithGenres(from: buffer)

        // Get Essentia predictions
        let moodPredictions = try await essentiaClassifier.predictMoodTheme(embeddings: embeddings)
        let instrumentPredictions = try await essentiaClassifier.predictInstruments(embeddings: embeddings)
        let genrePredictions = essentiaClassifier.labelGenres(activations: genreActivations)

        // Get top predictions
        let topMoods = essentiaClassifier.topPredictions(moodPredictions, count: topPredictionCount, threshold: predictionThreshold)
        let topInstruments = essentiaClassifier.topPredictions(instrumentPredictions, count: topPredictionCount, threshold: predictionThreshold)
        let topGenres = essentiaClassifier.topPredictions(genrePredictions, count: topPredictionCount, threshold: predictionThreshold)

        let essentiaTags = EssentiaTags(
            genres: topGenres.map { $0.tag },
            moods: topMoods.map { $0.tag },
            instruments: topInstruments.map { $0.tag }
        )

        return TaggingResult(
            userPredictions: nil,  // Can't use user model without knowing what features it expects
            essentiaTags: essentiaTags,
            embeddings: embeddings,
            genreActivations: genreActivations
        )
    }

    // MARK: - Private Helpers

    /// Categorize predicted tags into genre, timing, mood, and structured descriptive based on model metadata
    private func categorizePredictions(_ tags: [String]) -> UserTagPredictions {
        guard loadedMetadata != nil else {
            // No metadata - fall back to organizing descriptive tags only
            let organized = DescriptiveTagMapping.organize(tags)

            // Preserve tags not in DescriptiveTagMapping
            let knownTags = Set(organized.values.flatMap { $0 })
            let customTags = tags.filter { !knownTags.contains($0) }

            return UserTagPredictions(
                genre: nil,
                timing: nil,
                mood: nil,
                bassType: organized[.bassType]?.first,
                rhythm: organized[.rhythm] ?? [],
                style: organized[.style] ?? [],
                vibes: organized[.vibes] ?? [],
                instruments: organized[.instruments] ?? [],
                vocalType: organized[.vocalType]?.first,
                acapella: nil,
                customTags: customTags
            )
        }

        var genre: String? = nil
        var timing: String? = nil
        var moodTags: [String] = []
        var descriptiveTags: [String] = []

        // Use the dual-keyed (tag name + sanitized stem) deterministic lookup
        // built at model load — stem-named predictions ("Late_Night") must
        // categorize the same as their metadata tag names.
        for tag in tags {
            let category = tagCategoryLookup[tag.lowercased()] ?? "descriptive"

            switch category {
            case "genre":
                // Take first genre only (single-select)
                if genre == nil {
                    genre = tag
                }
            case "timing":
                // Take first timing only (single-select)
                if timing == nil {
                    timing = tag
                }
            case "mood":
                moodTags.append(tag)
            default:
                descriptiveTags.append(tag)
            }
        }

        // Join mood tags with comma for the mood field
        let moodString = moodTags.isEmpty ? nil : moodTags.joined(separator: ", ")

        // Organize descriptive tags by sub-category using DescriptiveTagMapping
        let organized = DescriptiveTagMapping.organize(descriptiveTags)

        // Extract multi-class results (BassType, VocalType) - only first value if present
        let bassType = organized[.bassType]?.first
        let vocalType = organized[.vocalType]?.first

        // Binary descriptive tags (excluding multi-class sub-categories)
        let rhythm = organized[.rhythm] ?? []
        let style = organized[.style] ?? []
        let vibes = organized[.vibes] ?? []
        let instruments = organized[.instruments] ?? []

        // Preserve custom tags not in DescriptiveTagMapping
        let knownTags = Set(organized.values.flatMap { $0 })
        let customTags = descriptiveTags.filter { !knownTags.contains($0) }

        return UserTagPredictions(
            genre: genre,
            timing: timing,
            mood: moodString,
            bassType: bassType,
            rhythm: rhythm,
            style: style,
            vibes: vibes,
            instruments: instruments,
            vocalType: vocalType,
            acapella: nil,
            customTags: customTags
        )
    }

    /// Get or create the fallback EffNet extractor (lazy initialization)
    private func getOrCreateEffNetExtractor() throws -> EffNetExtractor {
        if let extractor = effnetExtractor {
            return extractor
        }
        let extractor = try EffNetExtractor()
        effnetExtractor = extractor
        return extractor
    }

    // MARK: - Fallback Mapping Support

    /// Apply fallback mappings to generate user tag predictions from Essentia outputs.
    /// Judgment-stage (Timing) tags are never emitted — Stage 2's exclusive domain.
    func applyFallbackMappings(
        moodPredictions: [String: Float],
        genrePredictions: [String: Float],
        instrumentPredictions: [String: Float],
        excludingTrained: Set<String>
    ) -> [String] {
        var result: [String] = []

        for mapping in fallbackConfig.mappings {
            // Skip if we have a trained classifier for this tag
            if excludingTrained.contains(mapping.userTag.lowercased()) {
                continue
            }

            // Judgment-stage tags come only from Stage 2 — never from fallback
            if isJudgmentStageTag(mapping.userTag) {
                continue
            }

            // Skip if no Essentia labels configured
            guard !mapping.essentiaLabels.isEmpty else { continue }

            // Get the appropriate prediction dictionary based on source
            let predictions: [String: Float]
            switch mapping.essentiaSource {
            case .mood:
                predictions = moodPredictions
            case .genre:
                predictions = genrePredictions
            case .instrument:
                predictions = instrumentPredictions
            }

            // Check if ANY of the Essentia labels meet the user tag's resolved threshold
            let threshold = effectiveThreshold(forTag: mapping.userTag)
            let matchesThreshold = mapping.essentiaLabels.contains { label in
                if let probability = predictions[label] {
                    return probability >= threshold
                }
                return false
            }

            if matchesThreshold {
                result.append(mapping.userTag)
            }
        }

        return result
    }

    // MARK: - Hybrid Essentia Fallback

    /// Check if a low-confidence user prediction should be boosted by Essentia agreement
    /// - Parameters:
    ///   - tagName: The user tag name
    ///   - userConfidence: The user classifier's confidence (0 < confidence < threshold)
    ///   - moodPredictions: Essentia mood predictions
    ///   - genrePredictions: Essentia genre predictions
    ///   - instrumentPredictions: Essentia instrument predictions
    /// - Returns: True if the tag should be applied based on hybrid logic
    private func checkHybridEssentiaFallback(
        tagName: String,
        userConfidence: Float,
        moodPredictions: [String: Float],
        genrePredictions: [String: Float],
        instrumentPredictions: [String: Float]
    ) -> Bool {
        // Only boost if user confidence is at least 10% (avoid noise)
        guard userConfidence >= 0.1 else { return false }

        // Find the best matching Essentia prediction
        let essentiaConfidence = findBestEssentiaMatch(
            tagName: tagName,
            moodPredictions: moodPredictions,
            genrePredictions: genrePredictions,
            instrumentPredictions: instrumentPredictions
        )

        // If Essentia has no relevant prediction, can't boost
        guard essentiaConfidence > 0 else { return false }

        // Weighted combination: 50% user, 50% Essentia
        // This gives both signals equal weight in the final decision
        let combinedScore = (userConfidence * 0.5) + (essentiaConfidence * 0.5)

        return combinedScore >= classificationThreshold
    }

    /// Find the best matching Essentia prediction for a user tag
    private func findBestEssentiaMatch(
        tagName: String,
        moodPredictions: [String: Float],
        genrePredictions: [String: Float],
        instrumentPredictions: [String: Float]
    ) -> Float {
        // First, check if there's an explicit fallback mapping for this tag
        if let mapping = fallbackConfig.mapping(for: tagName), !mapping.essentiaLabels.isEmpty {
            let predictions: [String: Float]
            switch mapping.essentiaSource {
            case .mood: predictions = moodPredictions
            case .genre: predictions = genrePredictions
            case .instrument: predictions = instrumentPredictions
            }
            // Return the highest confidence among all mapped labels
            let maxConfidence = mapping.essentiaLabels.compactMap { predictions[$0] }.max() ?? 0
            if maxConfidence > 0 {
                return maxConfidence
            }
        }

        // No explicit mapping found — return 0 (no fuzzy matching)
        // Fuzzy string matching was removed because String.contains() produced
        // false positives (e.g., "house" matching "Ambient relaxing House music").
        // Use the Fallback Mappings editor to create explicit tag-to-Essentia mappings.
        return 0
    }

}
