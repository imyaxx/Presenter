import Foundation
import ModeKit

/// The file locations the app uses, resolved from the user's Application Support directory.
///
/// - The app's support directory `<Application Support>/<bundle id>/`, for `profiles.json` and `session.json`.
/// - The generated images directory `<support directory>/wallpapers/`.
/// - The system wallpaper store `<Application Support>/com.apple.wallpaper/Store/Index.plist` (ADR-027, S2).
///
/// Never creates a directory; the stores create what they write into.
struct SystemLocations: Equatable, Sendable {
    private static let wallpaperStorePath = "com.apple.wallpaper/Store/Index.plist"
    private static let generatedImagesFolder = "wallpapers"

    let supportDirectory: URL
    let wallpaperLocations: WallpaperLocations

    /// Pure resolution from an Application Support directory, injectable for tests.
    init(applicationSupportDirectory: URL, bundleIdentifier: String) {
        supportDirectory = applicationSupportDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
        wallpaperLocations = WallpaperLocations(
            storeURL: applicationSupportDirectory.appending(path: Self.wallpaperStorePath),
            generatedImagesDirectory: supportDirectory.appending(
                path: Self.generatedImagesFolder,
                directoryHint: .isDirectory,
            ),
        )
    }

    /// Resolves the current user's Application Support directory without creating it.
    ///
    /// - Throws: The error of `FileManager.url(for:in:appropriateFor:create:)`.
    static func current(bundleIdentifier: String, fileManager: FileManager) throws -> SystemLocations {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false,
        )
        return SystemLocations(applicationSupportDirectory: base, bundleIdentifier: bundleIdentifier)
    }
}
