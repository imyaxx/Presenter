import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Builds the composition from the app bundle the tests run in. Construction must not change anything.
struct PlatformCompositionTests {
    @Test
    func everyPortIsTheRealAdapter() throws {
        let ports = try PlatformComposition(bundle: .main, fileManager: .default).actionPorts

        #expect(ports.defaults is CFPreferencesDefaultsStore)
        #expect(ports.processRunner is FoundationProcessRunner)
        #expect(ports.appleScriptRunner is NSAppleScriptRunner)
        #expect(ports.workspace is AppKitWorkspaceAdapter)
        #expect(ports.notifier is DistributedNotificationCenterNotifier)
        #expect(ports.fileStore is FileManagerFileStore)
        #expect(ports.clock is SystemSessionClock)
        #expect(ports.imageRenderer is CoreGraphicsSolidColorImageRenderer)
        #expect(ports.storeInspector is PropertyListWallpaperStoreInspector)
    }

    @Test
    func locationsAndLoggerFollowTheBundleIdentifier() throws {
        let bundleIdentifier = try #require(Bundle.main.bundleIdentifier)
        let expected = try SystemLocations.current(bundleIdentifier: bundleIdentifier, fileManager: .default)
        let supportPath = expected.supportDirectory.path(percentEncoded: false)
        let existedBefore = FileManager.default.fileExists(atPath: supportPath)

        let composition = try PlatformComposition(bundle: .main, fileManager: .default)

        #expect(composition.supportDirectory == expected.supportDirectory)
        #expect(composition.wallpaperLocations == expected.wallpaperLocations)
        #expect(composition.sessionLogger is OSSessionLogger)
        #expect(FileManager.default.fileExists(atPath: supportPath) == existedBefore)
    }

    @Test
    func aBundleWithoutAnIdentifierIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "presenter-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try #require(Bundle(url: directory))

        #expect(throws: PlatformCompositionError.missingBundleIdentifier) {
            try PlatformComposition(bundle: bundle, fileManager: .default)
        }
    }
}
