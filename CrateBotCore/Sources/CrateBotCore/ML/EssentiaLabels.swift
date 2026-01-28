import Foundation

/// Labels for Essentia pre-trained classification heads
public enum EssentiaLabels {

    /// 56 Jamendo mood/theme tags
    public static let moodTheme: [String] = loadLabels(from: "mtg_jamendo_moodtheme-discogs-effnet-1")

    /// 40 Jamendo instrument tags
    public static let instruments: [String] = loadLabels(from: "mtg_jamendo_instrument-discogs-effnet-1")

    /// 400 Discogs genre tags
    public static let genres: [String] = loadLabels(from: "genre_discogs400-discogs-effnet-1")

    private static func loadLabels(from resourceName: String) -> [String] {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let classes = json["classes"] as? [String] else {
            return []
        }
        return classes
    }
}
