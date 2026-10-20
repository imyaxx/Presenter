#if DEBUG
import Foundation
import ModeKit

/// The real ports of ``PlatformComposition`` arranged for the tool (ADR-042): the workspace adapter records `hide`
/// and `unhide` results, generated images, profiles and `session.json` live in the check directory (never the app's
/// support directory), and session events are printed as well as logged.
struct AdapterCheckEnvironment: Sendable {
    let ports: ActionPorts
    let wallpaperLocations: WallpaperLocations
    let checkDirectory: URL
    let logger: PrintingSessionLogger

    init(composition: PlatformComposition, checkDirectory: URL, output: CheckOutput) {
        let real = composition.actionPorts
        ports = ActionPorts(
            defaults: real.defaults,
            processRunner: real.processRunner,
            appleScriptRunner: real.appleScriptRunner,
            workspace: RecordingWorkspaceAdapter(wrapping: real.workspace, output: output),
            notifier: real.notifier,
            fileStore: real.fileStore,
            clock: real.clock,
            imageRenderer: real.imageRenderer,
            storeInspector: real.storeInspector,
        )
        wallpaperLocations = WallpaperLocations(
            storeURL: composition.wallpaperLocations.storeURL,
            generatedImagesDirectory: checkDirectory.appending(path: "wallpapers", directoryHint: .isDirectory),
        )
        self.checkDirectory = checkDirectory
        logger = PrintingSessionLogger(output: output, forwardingTo: composition.sessionLogger)
    }

    func makeController() -> SessionController {
        SessionController(
            actionFactory: StandardActionFactory(ports: ports, wallpaperLocations: wallpaperLocations),
            sessionStore: SessionStore(fileStore: ports.fileStore, directory: checkDirectory),
            clock: ports.clock,
            logger: logger,
        )
    }

    func makeWorldReader() -> WorldReader {
        WorldReader(
            defaults: ports.defaults,
            fileStore: ports.fileStore,
            storeInspector: ports.storeInspector,
            workspace: ports.workspace,
            storeURL: wallpaperLocations.storeURL,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        )
    }

    func makeWallpaperRestorer() -> WallpaperRestorer {
        WallpaperRestorer(
            fileStore: ports.fileStore,
            processRunner: ports.processRunner,
            storeInspector: ports.storeInspector,
            storeURL: wallpaperLocations.storeURL,
        )
    }

    func loadProfiles() async throws -> [Profile] {
        try await ProfileStore(fileStore: ports.fileStore, directory: checkDirectory).loadProfiles()
    }
}
#endif
