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
            // Compression succeeded and is smaller
            return Data(bytes: destinationBuffer, count: compressedSize)
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

        // Estimate decompressed size (LZ4 typically 2-4x compression)
        let estimatedSize = data.count * 10
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: estimatedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourceBuffer in
            compression_decode_buffer(
                destinationBuffer,
                estimatedSize,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
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
