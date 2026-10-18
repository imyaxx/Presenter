import Foundation
import ModeKit

/// The composition root of the platform layer: the only place that instantiates the concrete adapters (docs/02).
///
/// Builds the ``ActionPorts`` (with ModeKit's `FileManagerFileStore` and `SystemSessionClock`), the wallpaper
/// locations, the app's support directory and the session logger. Construction has no side effect: nothing is
/// created on disk and no system call changes anything.
struct PlatformComposition {
    let actionPorts: ActionPorts
    let wallpaperLocations: WallpaperLocations
    let supportDirectory: URL
    let sessionLogger: any SessionLogger

    /// - Throws: ``PlatformCompositionError``.
    init(bundle: Bundle, fileManager: FileManager) throws(PlatformCompositionError) {
        guard let bundleIdentifier = bundle.bundleIdentifier else {
            throw PlatformCompositionError.missingBundleIdentifier
        }
        let locations: SystemLocations
        do {
            locations = try SystemLocations.current(bundleIdentifier: bundleIdentifier, fileManager: fileManager)
        } catch {
            throw PlatformCompositionError.applicationSupportUnavailable(reason: String(describing: error))
        }
        actionPorts = ActionPorts(
            defaults: CFPreferencesDefaultsStore(),
            processRunner: FoundationProcessRunner(),
            appleScriptRunner: NSAppleScriptRunner(),
            workspace: AppKitWorkspaceAdapter(),
            notifier: DistributedNotificationCenterNotifier(),
            fileStore: FileManagerFileStore(),
            clock: SystemSessionClock(),
            imageRenderer: CoreGraphicsSolidColorImageRenderer(),
            storeInspector: PropertyListWallpaperStoreInspector(),
        )
        wallpaperLocations = locations.wallpaperLocations
        supportDirectory = locations.supportDirectory
        sessionLogger = OSSessionLogger(subsystem: bundleIdentifier)
    }
}
