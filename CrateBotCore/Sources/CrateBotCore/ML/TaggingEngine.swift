import Foundation
import AVFoundation

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

    public init(
        userPredictions: UserTagPredictions? = nil,
        essentiaTags: EssentiaTags,
        embeddings: [Float],
        genreActivations: [Float]
    ) {
        self.userPredictions = userPredictions
        self.essentiaTags = essentiaTags
        self.embeddings = embeddings
        self.genreActivations = genreActivations
    }
}

public struct UserTagPredictions: Sendable {
    public let genre: String?
    public let timing: String?
    public let mood: String?
    public let descriptive: [String]

    public init(genre: String? = nil, timing: String? = nil, mood: String? = nil, descriptive: [String] = []) {
        self.genre = genre
        self.timing = timing
        self.mood = mood
        self.descriptive = descriptive
    }
}

/// Engine for analyzing audio with dual taxonomy (user + Essentia)
public actor TaggingEngine {
    private let effnetExtractor: EffNetExtractor
    private let essentiaClassifier: EssentiaClassifier
    private let audioAnalyzer: AudioAnalyzer

    /// User-trained classifiers (one per tag)
    private var userClassifiers: [TagClassifier] = []

    /// Loaded model name
    private var loadedModelName: String?

    /// Number of top predictions to keep for each category
    public var topPredictionCount: Int = 5

    /// Minimum probability threshold for Essentia predictions display
    public var predictionThreshold: Float = 0.2

    /// Classification threshold for user-trained classifiers (configurable via strictness setting)
    public var classificationThreshold: Float = 0.5

    /// Fallback mappings for tags without trained classifiers
    public var fallbackConfig: FallbackMappingConfig = FallbackMappingConfig()

    public init() throws {
        self.effnetExtractor = try EffNetExtractor()
        self.essentiaClassifier = try EssentiaClassifier()
        self.audioAnalyzer = AudioAnalyzer()
    }

    /// Load all classifiers from a model directory
    /// - Parameters:
    ///   - modelDirectory: Directory containing .mlmodel files and metadata JSON
    ///   - progress: Optional async callback for loading progress (0.0 to 1.0)
    /// - Returns: Number of classifiers loaded and the model name
    public func loadModel(
        from modelDirectory: URL,
        progress: ((Double) async -> Void)? = nil
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

        let totalFiles = modelFiles.count

        // Load each classifier
        for (index, modelURL) in modelFiles.enumerated() {
            let tagName = modelURL.deletingPathExtension().lastPathComponent
            do {
                let classifier = try TagClassifier(tagName: tagName, modelURL: modelURL, threshold: 0.5)
                userClassifiers.append(classifier)
            } catch {
                print("Warning: Failed to load classifier for '\(tagName)': \(error)")
            }

            // Report progress and yield to allow UI updates
            await progress?(Double(index + 1) / Double(totalFiles))
            await Task.yield()
        }

        // Get model name from directory or metadata
        let modelName = modelDirectory.lastPathComponent
        loadedModelName = modelName

        return (userClassifiers.count, modelName)
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
        loadedModelName = nil
    }

    /// Check if user model is loaded
    public var hasUserModel: Bool {
        !userClassifiers.isEmpty
    }

    /// Get loaded model name
    public var currentModelName: String? {
        loadedModelName
    }

    /// Get list of loaded tag classifiers
    public var loadedTags: [String] {
        userClassifiers.map { $0.tagName }
    }

    /// Get list of tags available via fallback mappings
    public var fallbackTags: [String] {
        fallbackConfig.enabled ? fallbackConfig.mappings.map { $0.userTag } : []
    }

    /// Update fallback mapping configuration
    public func setFallbackConfig(_ config: FallbackMappingConfig) {
        self.fallbackConfig = config
    }

    /// Update classification threshold (from strictness setting)
    public func setClassificationThreshold(_ threshold: Float) {
        self.classificationThreshold = threshold
    }

    /// Analyze audio file and return dual taxonomy predictions
    public func analyze(url: URL) async throws -> TaggingResult {
        // Load audio at 16kHz
        let buffer = try await audioAnalyzer.loadAudio(from: url, targetSampleRate: EffNetExtractor.targetSampleRate)

        // Extract EffNet embeddings and genre activations
        let (embeddings, genreActivations) = try await effnetExtractor.extractWithGenres(from: buffer)

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

        for classifier in userClassifiers {
            trainedTagNames.insert(classifier.tagName.lowercased())
            do {
                let (_, confidence) = try classifier.predictWithConfidence(features: embeddings)

                if confidence >= classificationThreshold {
                    // Confidence meets threshold - apply tag
                    predictedTags.append(classifier.tagName)
                } else if confidence > 0 {
                    // Below threshold but non-zero - try hybrid Essentia check
                    let shouldApply = checkHybridEssentiaFallback(
                        tagName: classifier.tagName,
                        userConfidence: confidence,
                        moodPredictions: moodPredictions,
                        genrePredictions: genrePredictions,
                        instrumentPredictions: instrumentPredictions
                    )
                    if shouldApply {
                        predictedTags.append(classifier.tagName)
                    }
                }
            } catch {
                print("Classifier '\(classifier.tagName)' failed: \(error)")
            }
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

        let userPredictions: UserTagPredictions? = predictedTags.isEmpty ? nil : UserTagPredictions(
            genre: nil,
            timing: nil,
            mood: nil,
            descriptive: predictedTags
        )

        return TaggingResult(
            userPredictions: userPredictions,
            essentiaTags: essentiaTags,
            embeddings: embeddings,
            genreActivations: genreActivations
        )
    }

    /// Analyze audio buffer directly (for cases where buffer is already loaded)
    public func analyze(buffer: AVAudioPCMBuffer) async throws -> TaggingResult {
        // Extract EffNet embeddings and genre activations
        let (embeddings, genreActivations) = try await effnetExtractor.extractWithGenres(from: buffer)

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

    // MARK: - Fallback Mapping Support

    /// Apply fallback mappings to generate user tag predictions from Essentia outputs
    private func applyFallbackMappings(
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

            // Check if ANY of the Essentia labels meet the global threshold
            let matchesThreshold = mapping.essentiaLabels.contains { label in
                if let probability = predictions[label] {
                    return probability >= classificationThreshold
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
        let normalizedTag = tagName.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

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

        // Otherwise, try fuzzy matching against Essentia labels
        var bestMatch: Float = 0

        // Check moods
        for (label, confidence) in moodPredictions {
            if fuzzyMatch(normalizedTag, label.lowercased()) {
                bestMatch = max(bestMatch, confidence)
            }
        }

        // Check genres
        for (label, confidence) in genrePredictions {
            if fuzzyMatch(normalizedTag, label.lowercased()) {
                bestMatch = max(bestMatch, confidence)
            }
        }

        // Check instruments
        for (label, confidence) in instrumentPredictions {
            if fuzzyMatch(normalizedTag, label.lowercased()) {
                bestMatch = max(bestMatch, confidence)
            }
        }

        return bestMatch
    }

    /// Simple fuzzy matching between a user tag and an Essentia label
    private func fuzzyMatch(_ userTag: String, _ essentiaLabel: String) -> Bool {
        // Exact match
        if userTag == essentiaLabel { return true }

        // Contains match (e.g., "funky" matches "funky/groove")
        if essentiaLabel.contains(userTag) || userTag.contains(essentiaLabel) { return true }

        // Common synonyms
        let synonyms: [String: [String]] = [
            "happy": ["fun", "joyful", "cheerful", "uplifting"],
            "sad": ["melancholic", "emotional", "dramatic"],
            "dark": ["dark", "heavy", "aggressive"],
            "chill": ["relaxing", "calm", "ambient"],
            "funky": ["groovy", "funk", "groove"],
            "dreamy": ["dream", "soundscape", "atmospheric"],
            "epic": ["epic", "dramatic", "film"],
            "energetic": ["energetic", "powerful", "action"],
            "jazzy": ["jazz"],
            "disco": ["disco", "dance"],
            "house": ["house", "electronic"],
            "techno": ["techno", "electronic"],
            "latin": ["latin", "tropical"],
            "soulful": ["soul", "rnb"],
            "aggressive": ["aggressive", "heavy", "hard"],
            "melodic": ["melodic", "soft", "mellow"],
            "bouncy": ["fun", "groovy", "upbeat"],
            "driving": ["energetic", "action", "powerful"]
        ]

        // Check if user tag has synonyms that match
        if let userSynonyms = synonyms[userTag] {
            for synonym in userSynonyms {
                if essentiaLabel.contains(synonym) { return true }
            }
        }

        // Check if Essentia label is a key with user tag as synonym
        for (key, values) in synonyms {
            if essentiaLabel.contains(key) && values.contains(userTag) {
                return true
            }
        }

        return false
    }
}
