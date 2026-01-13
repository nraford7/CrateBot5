import Foundation

/// CrateBotCore - Shared library for CrateBot applications
public enum CrateBotCore {
    public static let version = "1.0.0"
}

// Re-export all public types
@_exported import struct Foundation.Data
@_exported import struct Foundation.Date
@_exported import struct Foundation.URL
