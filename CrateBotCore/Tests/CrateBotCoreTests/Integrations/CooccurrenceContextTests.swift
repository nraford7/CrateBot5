import XCTest
@testable import CrateBotCore

final class CooccurrenceContextTests: XCTestCase {

    // MARK: - Helpers

    private func makeStats(
        baseRates: [String: Double],
        conditional: [String: [String: Double]],
        totalTracks: Int
    ) -> Cooccurrence.Stats {
        // Round-trip through JSON to honor the Decodable contract.
        let payload: [String: Any] = [
            "base_rates": baseRates,
            "conditional": conditional,
            "total_tracks": totalTracks
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return try! JSONDecoder().decode(Cooccurrence.Stats.self, from: data)
    }

    // MARK: - Tests

    func testCooccurrenceContextReturnsTopKAboveBaseRate() {
        // Synthetic stats: base_rates House=0.5, conditional["Peak"]={"House":0.9,"Dark":0.6,"Acapella":0.05}, total_tracks=100
        // Context for timing="Peak" topK=2 -> ["House", "Dark"] (Acapella excluded: below or near base rate)
        let stats = makeStats(
            baseRates: ["House": 0.5, "Dark": 0.3, "Acapella": 0.1331],
            conditional: ["Peak": ["House": 0.9, "Dark": 0.6, "Acapella": 0.05]],
            totalTracks: 100
        )

        let ctx = Cooccurrence.context(
            forTags: [],
            timing: "Peak",
            stats: stats,
            topK: 2,
            minSupport: 3,
            minLift: 1.2
        )

        // Lifts: Dark = 0.6/0.3 = 2.0 (rank 1), House = 0.9/0.5 = 1.8 (rank 2),
        // Acapella = 0.05/0.1331 ~= 0.376 (below 1.2, excluded).
        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.timingLabel, "Peak")
        XCTAssertEqual(ctx?.coOccurringTags, ["Dark", "House"])
        XCTAssertFalse(ctx?.coOccurringTags.contains("Acapella") ?? true)
        XCTAssertEqual(ctx?.support, 100)
    }

    func testCooccurrenceContextNilWhenSupportThin() {
        // total_tracks=1 -> nil
        let thinTotal = makeStats(
            baseRates: ["House": 0.5],
            conditional: ["Peak": ["House": 0.9]],
            totalTracks: 1
        )
        XCTAssertNil(Cooccurrence.context(
            forTags: [],
            timing: "Peak",
            stats: thinTotal
        ))

        // conditional["Peak"]={} -> nil
        let emptyRow = makeStats(
            baseRates: ["House": 0.5],
            conditional: ["Peak": [:]],
            totalTracks: 100
        )
        XCTAssertNil(Cooccurrence.context(
            forTags: [],
            timing: "Peak",
            stats: emptyRow
        ))

        // missing row entirely -> nil
        let missingRow = makeStats(
            baseRates: ["House": 0.5],
            conditional: [:],
            totalTracks: 100
        )
        XCTAssertNil(Cooccurrence.context(
            forTags: [],
            timing: "Peak",
            stats: missingRow
        ))
    }

    func testCooccurrenceContextExcludesTrivialFrequencyArtifacts() {
        // "Common" appears with high P(Common|Peak)=0.85, but base_rate=0.80 -> lift=1.0625, below 1.2 -> excluded.
        // "Signal" has P=0.50, base_rate=0.20 -> lift=2.5 -> included.
        let stats = makeStats(
            baseRates: ["Common": 0.80, "Signal": 0.20],
            conditional: ["Peak": ["Common": 0.85, "Signal": 0.50]],
            totalTracks: 200
        )

        let ctx = Cooccurrence.context(
            forTags: [],
            timing: "Peak",
            stats: stats,
            topK: 3,
            minSupport: 3,
            minLift: 1.2
        )

        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.coOccurringTags, ["Signal"])
        XCTAssertFalse(ctx?.coOccurringTags.contains("Common") ?? true)
    }
}
