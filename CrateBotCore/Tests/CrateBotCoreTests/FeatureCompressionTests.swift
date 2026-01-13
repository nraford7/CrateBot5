import XCTest
@testable import CrateBotCore

final class FeatureCompressionTests: XCTestCase {
    func testRoundTrip() throws {
        let original: [Float] = [1.0, 2.5, -3.7, 0.0, 100.123]

        let compressed = original.toCompressedData()
        let decompressed = try [Float].fromCompressedData(compressed)

        XCTAssertEqual(original, decompressed)
    }

    func testCompressionReducesSize() throws {
        // Create a large array with repeating patterns (compresses well)
        let original = [Float](repeating: 1.0, count: 10000)

        let uncompressedSize = original.count * MemoryLayout<Float>.size
        let compressed = original.toCompressedData()

        XCTAssertLessThan(compressed.count, uncompressedSize)
    }

    func testEmptyArray() throws {
        let original: [Float] = []

        let compressed = original.toCompressedData()
        let decompressed = try [Float].fromCompressedData(compressed)

        XCTAssertEqual(original, decompressed)
    }

    func testLargeArray() throws {
        // 512-dimensional feature vector typical for audio
        let original = (0..<512).map { Float($0) * 0.001 }

        let compressed = original.toCompressedData()
        let decompressed = try [Float].fromCompressedData(compressed)

        XCTAssertEqual(original, decompressed)
    }
}
