import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Builds the real graph without starting it: nothing is read, written or created.
@MainActor
struct AppEnvironmentTests {
    @Test
    func theGraphBuildsWithoutSideEffects() throws {
        let bundleIdentifier = try #require(Bundle.main.bundleIdentifier)
        let support = try SystemLocations.current(bundleIdentifier: bundleIdentifier, fileManager: .default)
        let path = support.supportDirectory.path(percentEncoded: false)
        let existedBefore = FileManager.default.fileExists(atPath: path)

        let environment = AppEnvironment(bundle: .main, fileManager: .default)

        #expect(environment.viewModel.presentation == .recoveringAtLaunch)
        #expect(environment.quitCoordinator != nil)
        #expect(FileManager.default.fileExists(atPath: path) == existedBefore)
    }

    @Test
    func aBundleWithoutAnIdentifierGivesAnUnavailableApp() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "presenter-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try #require(Bundle(url: directory))

        let environment = AppEnvironment(bundle: bundle, fileManager: .default)
        environment.start()

        #expect(environment.viewModel.presentation == .unavailable)
        #expect(environment.quitCoordinator == nil)
        environment.stop()
    }
}
