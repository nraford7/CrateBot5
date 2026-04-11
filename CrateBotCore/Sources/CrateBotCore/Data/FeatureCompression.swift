import Foundation
import Compression

public enum FeatureCompressionError: Error {
    case decompressionFailed
    case invalidData
}

extension Array where Element == Float {
    /// Compress float array to LZ4-compressed Data
    public func toCompressedData() -> Data {
        guard !isEmpty else { return Data() }

        let byteCount = count * MemoryLayout<Float>.size
        let bytes = withUnsafeBytes { Data($0) }

        // Try to compress with LZ4
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        defer { destinationBuffer.deallocate() }

        let compressedSize = bytes.withUnsafeBytes { sourceBuffer in
            compression_encode_buffer(
                destinationBuffer,
                byteCount,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                byteCount,
                nil,
                COMPRESSION_LZ4
            )
        }

        if compressedSize > 0 && compressedSize < byteCount {
            // Prepend original byte count as 4-byte little-endian UInt32
            var size = UInt32(byteCount).littleEndian
            var result = Data(bytes: &size, count: 4)
            result.append(Data(bytes: destinationBuffer, count: compressedSize))
            return result
        } else {
            // Return uncompressed data with marker
            var result = Data([0xFF])  // Marker for uncompressed
            result.append(bytes)
            return result
        }
    }

    /// Decompress LZ4-compressed Data to float array
    public static func fromCompressedData(_ data: Data) throws -> [Float] {
        guard !data.isEmpty else { return [] }

        // Check for uncompressed marker
        if data.first == 0xFF {
            let bytes = data.dropFirst()
            let count = bytes.count / MemoryLayout<Float>.size
            return bytes.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self).prefix(count))
            }
        }

        // Read original byte count from first 4 bytes
        let originalSize: Int
        let compressedData: Data
        if data.count >= 4 {
            let sizeBytes = data.prefix(4)
            let storedSize = sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
            originalSize = Int(storedSize)
            compressedData = data.dropFirst(4)
        } else {
            // Legacy format without size header — fall back to estimate
            originalSize = data.count * 10
            compressedData = data
        }

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: originalSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = compressedData.withUnsafeBytes { sourceBuffer in
            compression_decode_buffer(
                destinationBuffer,
                originalSize,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                compressedData.count,
                nil,
                COMPRESSION_LZ4
            )
        }

        guard decompressedSize > 0 else {
            throw FeatureCompressionError.decompressionFailed
        }

        let floatCount = decompressedSize / MemoryLayout<Float>.size
        let floatBuffer = UnsafeRawPointer(destinationBuffer).bindMemory(to: Float.self, capacity: floatCount)
        return Array(UnsafeBufferPointer(start: floatBuffer, count: floatCount))
    }
}
