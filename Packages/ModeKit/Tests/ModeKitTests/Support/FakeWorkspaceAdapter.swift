import Foundation
import ModeKit

/// A stateful ``WorkspaceAdapter``: `hide` and `unhide` change the listed applications, with an ordered call log,
/// scripted responses per application, and helpers that change the world the way the user or the system would.
/// Displays are settable; `setDesktopImage` can fail per display and otherwise hands the image to the
/// ``FakeWallpaperStore``, whose agent persists it later.
actor FakeWorkspaceAdapter: WorkspaceAdapter {
    enum Call: Equatable, Sendable {
        case list
        case hide(BundleIdentifier)
        case unhide(BundleIdentifier)
        case connectedDisplays
        case setDesktopImage(URL, DisplayIdentifier)
    }

    /// Thrown by `setDesktopImage` for a display that is not connected.
    struct DisplayNotConnected: Error, Equatable {
        let display: DisplayIdentifier
    }

    enum Operation: Hashable, Sendable {
        case hide, unhide
    }

    private struct ScriptKey: Hashable {
        let operation: Operation
        let application: BundleIdentifier
    }

    /// The whole world, for comparing before and after a session.
    private(set) var applications: [RunningApplication]
    private(set) var calls: [Call] = []
    private var scripted: [ScriptKey: ApplicationVisibilityChange] = [:]
    private(set) var displays: [DisplayIdentifier]
    private var desktopImageFailures: [DisplayIdentifier: any Error] = [:]
    private let wallpaperStore: FakeWallpaperStore?

    init(
        _ applications: [RunningApplication] = [],
        displays: [DisplayIdentifier] = [],
        wallpaperStore: FakeWallpaperStore? = nil,
    ) {
        self.applications = applications
        self.displays = displays
        self.wallpaperStore = wallpaperStore
    }

    /// Replaces the connected displays, as plugging or unplugging would.
    func connect(_ displays: [DisplayIdentifier]) {
        self.displays = displays
    }

    /// Makes every `setDesktopImage` on `display` throw `error`.
    func failSetDesktopImage(on display: DisplayIdentifier, with error: any Error) {
        desktopImageFailures[display] = error
    }

    /// Makes every `operation` on `application` return `.refused` and change nothing, until ``allow(_:of:)``.
    func refuse(_ operation: Operation, of application: BundleIdentifier) {
        scripted[ScriptKey(operation: operation, application: application)] = .refused
    }

    /// Makes the application quit just before the next `operation` on it reaches it: the call returns `.notRunning`.
    func quitBefore(_ operation: Operation, of application: BundleIdentifier) {
        scripted[ScriptKey(operation: operation, application: application)] = .notRunning
    }

    /// Removes a scripted response.
    func allow(_ operation: Operation, of application: BundleIdentifier) {
        scripted[ScriptKey(operation: operation, application: application)] = nil
    }

    /// The user chose Show All or clicked the application's Dock icon.
    func userUnhides(_ application: BundleIdentifier) {
        update(application) { $0.with(.visible) }
    }

    /// The user switched to the application: it becomes frontmost and visible.
    func activate(_ application: BundleIdentifier) {
        applications = applications.map { running in
            let isTarget = running.bundleIdentifier == application
            return RunningApplication(
                bundleIdentifier: running.bundleIdentifier,
                isHidden: isTarget ? false : running.isHidden,
                isFrontmost: isTarget,
                isThisApplication: running.isThisApplication,
            )
        }
    }

    func quit(_ application: BundleIdentifier) {
        applications.removeAll { $0.bundleIdentifier == application }
    }

    func launch(_ application: RunningApplication) {
        applications.append(application)
    }

    func runningApplications() async -> [RunningApplication] {
        calls.append(.list)
        return applications
    }

    func connectedDisplays() async -> [DisplayIdentifier] {
        calls.append(.connectedDisplays)
        return displays
    }

    func setDesktopImage(_ image: URL, on display: DisplayIdentifier) async throws {
        calls.append(.setDesktopImage(image, display))
        if let error = desktopImageFailures[display] {
            throw error
        }
        guard displays.contains(display) else {
            throw DisplayNotConnected(display: display)
        }
        await wallpaperStore?.agentReceived(image, on: display)
    }

    func hide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        calls.append(.hide(application))
        return change(application, by: .hide, to: .hidden)
    }

    func unhide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        calls.append(.unhide(application))
        return change(application, by: .unhide, to: .visible)
    }

    private func change(
        _ application: BundleIdentifier,
        by operation: Operation,
        to visibility: RunningApplication.Visibility,
    ) -> ApplicationVisibilityChange {
        switch scripted[ScriptKey(operation: operation, application: application)] {
        case .refused:
            return .refused
        case .notRunning:
            scripted[ScriptKey(operation: operation, application: application)] = nil
            quit(application)
            return .notRunning
        case .changed, nil:
            guard applications.contains(where: { $0.bundleIdentifier == application }) else {
                return .notRunning
            }
            update(application) { $0.with(visibility) }
            return .changed
        }
    }

    private func update(_ application: BundleIdentifier, _ transform: (RunningApplication) -> RunningApplication) {
        applications = applications.map { $0.bundleIdentifier == application ? transform($0) : $0 }
    }
}
