import XCTest
@testable import CrateBotCore

final class StratifiedSamplerTests: XCTestCase {

    func testSampleSizePresets() {
        XCTAssertEqual(SampleSize.quick.count, 25)
        XCTAssertEqual(SampleSize.small.count, 50)
        XCTAssertEqual(SampleSize.balanced.count, 100)
        XCTAssertEqual(SampleSize.large.count, 250)
    }

    func testStratifiedSamplingPreservesDistribution() {
        // Create tracks with known tag distribution
        // 60% House, 30% Techno, 10% Disco
        var tracks: [TaggedTrack] = []
        for i in 0..<100 {
            let tag: String
            if i < 60 { tag = "House" }
            else if i < 90 { tag = "Techno" }
            else { tag = "Disco" }
            tracks.append(TaggedTrack(id: "\(i)", tags: [tag]))
        }

        let sampler = StratifiedSampler()
        let sample = sampler.sample(from: tracks, size: .small, stratifyBy: \.primaryTag)

        XCTAssertEqual(sample.count, 50)

        // Check distribution is roughly preserved (within 10%)
        let houseCount = sample.filter { $0.tags.contains("House") }.count
        let technoCount = sample.filter { $0.tags.contains("Techno") }.count
        let discoCount = sample.filter { $0.tags.contains("Disco") }.count

        // 60% of 50 = 30, allow +/-5
        XCTAssertTrue((25...35).contains(houseCount), "House count \(houseCount) not in expected range")
        // 30% of 50 = 15, allow +/-5
        XCTAssertTrue((10...20).contains(technoCount), "Techno count \(technoCount) not in expected range")
        // 10% of 50 = 5, allow +/-3
        XCTAssertTrue((2...8).contains(discoCount), "Disco count \(discoCount) not in expected range")
    }

    func testFullSampleReturnsAllTracks() {
        let tracks = (0..<100).map { TaggedTrack(id: "\($0)", tags: ["Tag"]) }
        let sampler = StratifiedSampler()

        let sample = sampler.sample(from: tracks, size: .full, stratifyBy: \.primaryTag)

        XCTAssertEqual(sample.count, tracks.count)
    }

    func testSampleSmallerThanRequestedReturnsAll() {
        let tracks = (0..<20).map { TaggedTrack(id: "\($0)", tags: ["Tag"]) }
        let sampler = StratifiedSampler()

        let sample = sampler.sample(from: tracks, size: .balanced, stratifyBy: \.primaryTag)

        XCTAssertEqual(sample.count, 20) // Only 20 available, requested 100
    }

    func testDeterministicWithSameSeed() {
        let tracks = (0..<100).map { TaggedTrack(id: "\($0)", tags: ["\($0 % 3)"]) }
        let sampler = StratifiedSampler(seed: 42)

        let sample1 = sampler.sample(from: tracks, size: .small, stratifyBy: \.primaryTag)

        let sampler2 = StratifiedSampler(seed: 42)
        let sample2 = sampler2.sample(from: tracks, size: .small, stratifyBy: \.primaryTag)

        XCTAssertEqual(sample1.map(\.id), sample2.map(\.id))
    }
}

extension TaggedTrack {
    var primaryTag: String {
        tags.first ?? "Unknown"
    }
}
