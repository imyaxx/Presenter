import Foundation
import ModeKit
import Testing

@testable import PresenterApp

struct SystemLocationsTests {
    private let locations = SystemLocations(
        applicationSupportDirectory: URL(filePath: "/Base/Application Support", directoryHint: .isDirectory),
        bundleIdentifier: "dev.example.app",
    )

    @Test
    func theSupportDirectoryIsNamedAfterTheBundleIdentifier() {
        #expect(locations.supportDirectory.path(percentEncoded: false) == "/Base/Application Support/dev.example.app/")
    }

    @Test
    func generatedImagesLiveInTheSupportDirectory() {
        #expect(
            locations.wallpaperLocations.generatedImagesDirectory.path(percentEncoded: false)
                == "/Base/Application Support/dev.example.app/wallpapers/")
    }

    @Test
    func theWallpaperStoreIsTheSystemStore() {
        #expect(
            locations.wallpaperLocations.storeURL.path(percentEncoded: false)
                == "/Base/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    @Test
    func theCurrentUserResolutionCreatesNothing() throws {
        let bundleIdentifier = "dev.imyaxx.presenter.tests.\(UUID().uuidString)"

        let current = try SystemLocations.current(bundleIdentifier: bundleIdentifier, fileManager: .default)

        #expect(current.supportDirectory.lastPathComponent == bundleIdentifier)
        #expect(!FileManager.default.fileExists(atPath: current.supportDirectory.path(percentEncoded: false)))
    }
}
