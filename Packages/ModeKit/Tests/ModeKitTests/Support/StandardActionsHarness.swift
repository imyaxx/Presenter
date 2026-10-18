import Foundation
import ModeKit

/// Real ``SessionController``, ``StandardActionFactory`` and ``SessionStore`` over ``InMemoryFileStore``, with the
/// stateful port fakes. ``makeController()`` builds a fresh controller and factory over the same fakes, as a relaunch
/// after a crash would.
struct StandardActionsHarness {
    static let createDesktop = DefaultsKey(domain: "com.apple.finder", name: "CreateDesktop")
    static let autohide = DefaultsKey(domain: "com.apple.dock", name: "autohide")
    static let menuBarOption = DefaultsKey(domain: "com.apple.controlcenter", name: "AutoHideMenuBarOption")
    static let hideMenuBar = DefaultsKey(domain: "NSGlobalDomain", name: "_HIHideMenuBar")
    static let menuBarInFullscreen = DefaultsKey(domain: "NSGlobalDomain", name: "AppleMenuBarVisibleInFullscreen")
    static let profile = ProfileBuilder(steps: [.hideDesktopIcons, .hideDock]).build()

    /// Desktop icons, Dock, menu bar and hide apps, in that order.
    static func fourStepProfile(excluding exclusions: Set<BundleIdentifier>) -> Profile {
        ProfileBuilder(steps: [.hideDesktopIcons, .hideDock, .hideMenuBar, .hideApps(exclusions: exclusions)]).build()
    }

    let defaults: FakeDefaultsStore
    let processRunner = FakeProcessRunner()
    let scripts: FakeAppleScriptRunner
    let workspace: FakeWorkspaceAdapter
    let notifier = FakeDistributedNotifier()
    let fileStore = InMemoryFileStore()
    let logger = RecordingSessionLogger()

    init(initial: [DefaultsKey: DefaultsValue], applications: [RunningApplication] = []) {
        let defaults = FakeDefaultsStore(initial)
        self.defaults = defaults
        scripts = FakeAppleScriptRunner(systemEvents: defaults)
        workspace = FakeWorkspaceAdapter(applications)
    }

    func makeController() -> SessionController {
        let factory = StandardActionFactory(
            defaults: defaults,
            processRunner: processRunner,
            appleScriptRunner: scripts,
            workspace: workspace,
            notifier: notifier,
        )
        return SessionController(
            actionFactory: factory,
            sessionStore: SessionStore(fileStore: fileStore, directory: SessionControllerHarness.directory),
            clock: FakeClock(),
            logger: logger,
        )
    }

    func sessionFile() async -> Data? {
        await fileStore.contents(of: SessionControllerHarness.sessionFileURL)
    }
}
