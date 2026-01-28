import Foundation

/// Essentia-predicted tags for secondary ID3 fields
public struct EssentiaTags: Codable, Sendable, Equatable {
    /// Top Discogs genres (e.g., "Deep House, Tech House, Minimal")
    public let genres: [String]

    /// Top mood/theme tags (e.g., "energetic, dark, groovy")
    public let moods: [String]

    /// Detected instruments (e.g., "synthesizer, drums, bass")
    public let instruments: [String]

    public init(genres: [String] = [], moods: [String] = [], instruments: [String] = []) {
        self.genres = genres
        self.moods = moods
        self.instruments = instruments
    }

    /// Format for ID3 field (comma-separated)
    public var genresString: String { genres.joined(separator: ", ") }
    public var moodsString: String { moods.joined(separator: ", ") }
    public var instrumentsString: String { instruments.joined(separator: ", ") }

    /// Extract the top subgenre from genre predictions
    /// Genres are in format "MainGenre---Subgenre" (e.g., "Electronic---Deep House")
    /// Returns just the subgenre portion (e.g., "Deep House")
    public var topSubGenre: String? {
        guard let firstGenre = genres.first else { return nil }
        if firstGenre.contains("---") {
            let parts = firstGenre.components(separatedBy: "---")
            return parts.count > 1 ? parts[1] : firstGenre
        }
        return firstGenre
    }

    /// Check if all fields are empty
    public var isEmpty: Bool {
        genres.isEmpty && moods.isEmpty && instruments.isEmpty
    }
}
