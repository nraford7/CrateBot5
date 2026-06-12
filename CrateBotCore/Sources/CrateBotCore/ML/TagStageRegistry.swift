import Foundation

/// Maps tag categories to pipeline stages.
/// Stage 1 (perception): tags predictable from audio alone.
/// Stage 2 (judgment): tags encoding DJ intent, learned from Stage 1 outputs.
public enum TagStage: String, Codable, Sendable {
    case perception
    case judgment
}

/// Category-level registry deciding which pipeline stage owns each tag category.
///
/// Tags arrive pre-categorized by ID3 field (TCON = Genre, TALB = Timing,
/// TIT1 = Mood, COMM = Descriptive), so a category-level mapping is sufficient:
/// every relational tag (Start, Build, Peak, Sustain, Release) reaches the
/// collector through the Timing field. Unknown categories default to
/// `.perception` — the safe choice, since Stage 2 only ever handles tags it
/// was explicitly trained for.
public struct TagStageRegistry: Sendable {
    private let categoryToStage: [String: TagStage]

    public init(categoryToStage: [String: TagStage] = Self.defaultMapping) {
        self.categoryToStage = categoryToStage
    }

    public static let defaultMapping: [String: TagStage] = [
        "Genre": .perception,
        "Mood": .perception,
        "Descriptive": .perception,
        "Timing": .judgment,
    ]

    /// The stage responsible for a tag category. Unknown categories are perception.
    public func stage(forCategory category: String) -> TagStage {
        categoryToStage[category] ?? .perception
    }

    /// All categories owned by a stage, sorted for deterministic output.
    public func categories(in stage: TagStage) -> [String] {
        categoryToStage.filter { $0.value == stage }.map(\.key).sorted()
    }
}
