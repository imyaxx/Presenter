import AppKit

/// Starts the session at launch and restores an active session before the app quits (ADR-043).
///
/// Quit from the popover and Cmd+Q both arrive in ``applicationShouldTerminate(_:)``.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Nil when the process hosts the unit tests: no session graph is built (``LaunchMode``).
    let environment: AppEnvironment?
    private var quitting: Task<Void, Never>?

    override init() {
        switch LaunchMode.current(environment: ProcessInfo.processInfo.environment) {
        case .application: environment = AppEnvironment(bundle: .main, fileManager: .default)
        case .testHost: environment = nil
        }
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        environment?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator = environment?.quitCoordinator else {
            return .terminateNow
        }
        guard quitting == nil else {
            return .terminateLater
        }
        quitting = Task { [environment] in
            _ = await coordinator.prepareToQuit()
            environment?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
