import Foundation
import AVFoundation

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

    /// Optional user-trained model
    private var userClassifier: TagClassifier?

    /// Number of top predictions to keep for each category
    public var topPredictionCount: Int = 5

    /// Minimum probability threshold for predictions
    public var predictionThreshold: Float = 0.2

    public init() throws {
        self.effnetExtractor = try EffNetExtractor()
        self.essentiaClassifier = try EssentiaClassifier()
        self.audioAnalyzer = AudioAnalyzer()
    }

    /// Load user-trained model
    public func loadUserModel(from url: URL) throws {
        self.userClassifier = try TagClassifier(tagName: "user", modelURL: url, threshold: 0.5)
    }

    /// Unload user model
    public func unloadUserModel() {
        self.userClassifier = nil
    }

    /// Check if user model is loaded
    public var hasUserModel: Bool {
        userClassifier != nil
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

        // Get user predictions if model loaded
        var userPredictions: UserTagPredictions? = nil
        if let classifier = userClassifier {
            do {
                let (result, _) = try classifier.predictWithConfidence(features: embeddings)
                // Binary classifier returns single tag prediction
                if result {
                    userPredictions = UserTagPredictions(
                        genre: nil,
                        timing: nil,
                        mood: nil,
                        descriptive: [classifier.tagName]
                    )
                }
            } catch {
                // User model prediction failed, continue without it
                print("User model prediction failed: \(error)")
            }
        }

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
}
