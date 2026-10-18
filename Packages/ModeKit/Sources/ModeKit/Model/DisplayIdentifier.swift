import Foundation

/// A display, identified by its display UUID.
///
/// Whether the UUID stays stable across reboot and reconnection is unverified (docs/07-macos-integration.md).
/// Persisted as the UUID string.
public struct DisplayIdentifier: Codable, Hashable, Sendable, Comparable {
    /// The display UUID.
    public let uuid: UUID

    /// Wraps a display UUID.
    public init(uuid: UUID) {
        self.uuid = uuid
    }

    public init(from decoder: any Decoder) throws {
        uuid = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid)
    }

    public static func < (lhs: DisplayIdentifier, rhs: DisplayIdentifier) -> Bool {
        lhs.uuid.uuidString < rhs.uuid.uuidString
    }
}
