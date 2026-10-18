import Foundation

/// An opaque digest of the wallpaper configuration in a wallpaper store, produced by ``WallpaperStoreInspector``.
///
/// Only equality is meaningful: equal fingerprints mean equal wallpaper configuration. Persisted as base64 data.
public struct WallpaperStoreFingerprint: Codable, Hashable, Sendable {
    /// The digest bytes, in a form only the inspector understands.
    public let data: Data

    /// Wraps digest bytes.
    public init(data: Data) {
        self.data = data
    }
}
