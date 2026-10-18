import Foundation

/// Where the wallpaper action finds the system's wallpaper store and keeps its generated images.
///
/// A plain value: ModeKit never resolves home or bundle paths; the composition root injects them, like the profiles
/// directory.
public struct WallpaperLocations: Hashable, Sendable {
    /// The wallpaper store file (`Index.plist`, ADR-027).
    public let storeURL: URL
    /// The directory for generated solid-color PNG files, kept as a small cache.
    public let generatedImagesDirectory: URL

    /// Creates the locations.
    public init(storeURL: URL, generatedImagesDirectory: URL) {
        self.storeURL = storeURL
        self.generatedImagesDirectory = generatedImagesDirectory
    }
}
