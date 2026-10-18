import Foundation
import ModeKit

/// Real ``SessionController``, ``StandardActionFactory`` and ``SessionStore`` over ``InMemoryFileStore``, with the
/// stateful port fakes. ``makeController()`` builds a fresh controller and factory over the same fakes, as a relaunch
/// after a crash would. The session file and the wallpaper store share one ``InMemoryFileStore``; the wallpaper
/// action's polling sleeps on a separate ``FakeClock`` in immediate mode.
struct StandardActionsHarness {
    static let createDesktop = DefaultsKey(domain: "com.apple.finder", name: "CreateDesktop")
    static let autohide = DefaultsKey(domain: "com.apple.dock", name: "autohide")
    static let menuBarOption = DefaultsKey(domain: "com.apple.controlcenter", name: "AutoHideMenuBarOption")
    static let hideMenuBar = DefaultsKey(domain: "NSGlobalDomain", name: "_HIHideMenuBar")
    static let menuBarInFullscreen = DefaultsKey(domain: "NSGlobalDomain", name: "AppleMenuBarVisibleInFullscreen")
    static let wallpaperLocations = WallpaperLocations(
        storeURL: URL(filePath: "/fake/wallpaper/Index.plist"),
        generatedImagesDirectory: URL(filePath: "/fake/support/wallpapers", directoryHint: .isDirectory),
    )
    static let profile = ProfileBuilder(steps: [.hideDesktopIcons, .hideDock]).build()

    /// Desktop icons, Dock, menu bar and hide apps, in that order.
    static func fourStepProfile(excluding exclusions: Set<BundleIdentifier>) -> Profile {
        ProfileBuilder(steps: [.hideDesktopIcons, .hideDock, .hideMenuBar, .hideApps(exclusions: exclusions)]).build()
    }

    /// Desktop icons, Dock, menu bar, hide apps and wallpaper, in that order.
    static func fiveStepProfile(
        excluding exclusions: Set<BundleIdentifier>,
        wallpaper: WallpaperChoice,
        displays: DisplaySelection,
    ) -> Profile {
        let steps: [ProfileStep] = [
            .hideDesktopIcons, .hideDock, .hideMenuBar, .hideApps(exclusions: exclusions),
            .wallpaper(wallpaper, displays: displays),
        ]
        return ProfileBuilder(steps: steps).build()
    }

    let defaults: FakeDefaultsStore
    let processRunner = FakeProcessRunner()
    let scripts: FakeAppleScriptRunner
    let workspace: FakeWorkspaceAdapter
    let notifier = FakeDistributedNotifier()
    let fileStore = InMemoryFileStore()
    let wallpaperStore: FakeWallpaperStore
    let imageRenderer = FakeSolidColorImageRenderer()
    let actionClock = FakeClock(sleeping: .immediate)
    let logger = RecordingSessionLogger()

    init(
        initial: [DefaultsKey: DefaultsValue],
        applications: [RunningApplication] = [],
        wallpapers: [DisplayIdentifier: String] = [:],
    ) async {
        let defaults = FakeDefaultsStore(initial)
        self.defaults = defaults
        scripts = FakeAppleScriptRunner(systemEvents: defaults)
        let wallpaperStore = await FakeWallpaperStore.make(
            in: fileStore,
            at: Self.wallpaperLocations.storeURL,
            wallpapers: wallpapers,
        )
        self.wallpaperStore = wallpaperStore
        workspace = FakeWorkspaceAdapter(
            applications,
            displays: wallpapers.keys.sorted(),
            wallpaperStore: wallpaperStore,
        )
    }

    func makeController() -> SessionController {
        let ports = ActionPorts(
            defaults: defaults,
            processRunner: processRunner,
            appleScriptRunner: scripts,
            workspace: workspace,
            notifier: notifier,
            fileStore: fileStore,
            clock: actionClock,
            imageRenderer: imageRenderer,
            storeInspector: FakeWallpaperStoreInspector(),
        )
        return SessionController(
            actionFactory: StandardActionFactory(ports: ports, wallpaperLocations: Self.wallpaperLocations),
            sessionStore: SessionStore(fileStore: fileStore, directory: SessionControllerHarness.directory),
            clock: FakeClock(),
            logger: logger,
        )
    }

    func sessionFile() async -> Data? {
        await fileStore.contents(of: SessionControllerHarness.sessionFileURL)
    }

    func wallpaperStoreData() async -> Data? {
        await fileStore.contents(of: Self.wallpaperLocations.storeURL)
    }
}
