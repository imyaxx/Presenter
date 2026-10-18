import Foundation
import ModeKit

/// Real ``SessionController``, ``StandardActionFactory`` and ``SessionStore`` over ``InMemoryFileStore``, with the
/// stateful port fakes. ``makeController()`` builds a fresh controller and factory over the same fakes, as a relaunch
/// after a crash would.
struct StandardActionsHarness {
    static let createDesktop = DefaultsKey(domain: "com.apple.finder", name: "CreateDesktop")
    static let autohide = DefaultsKey(domain: "com.apple.dock", name: "autohide")
    static let profile = ProfileBuilder(steps: [.hideDesktopIcons, .hideDock]).build()

    let defaults: FakeDefaultsStore
    let processRunner = FakeProcessRunner()
    let scripts: FakeAppleScriptRunner
    let fileStore = InMemoryFileStore()
    let logger = RecordingSessionLogger()

    init(initial: [DefaultsKey: DefaultsValue]) {
        let defaults = FakeDefaultsStore(initial)
        self.defaults = defaults
        scripts = FakeAppleScriptRunner(systemEvents: defaults)
    }

    func makeController() -> SessionController {
        let factory = StandardActionFactory(
            defaults: defaults,
            processRunner: processRunner,
            appleScriptRunner: scripts,
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
