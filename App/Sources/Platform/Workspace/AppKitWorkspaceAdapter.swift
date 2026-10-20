import AppKit
import ModeKit

/// The real ``WorkspaceAdapter``: `NSWorkspace`, `NSRunningApplication` and `NSScreen` (ADR-036, ADR-038, ADR-040).
///
/// Every AppKit call hops to the main actor inside the async method. `hide` and `unhide` ask every instance, then
/// watch `isHidden` for up to ``visibilityTimeout``: `changed` means every instance reached the wanted state, `refused`
/// that one did not in time. The `Bool` that `NSRunningApplication.hide()` returns is ignored: on macOS 27.0.1 it
/// returned `false` while the application did hide (adapter check C6, 2026-10-20). `setDesktopImage` changes the
/// current Space of one display only (S2).
///
/// Threading: a value type; methods may be called from any context.
struct AppKitWorkspaceAdapter: WorkspaceAdapter {
    func runningApplications() async -> [RunningApplication] {
        await MainActor.run { Self.regularApplications() }
    }

    /// How long `hide` and `unhide` watch for the effect, and how often.
    static let visibilityTimeout = Duration.seconds(2)
    static let visibilityPollInterval = Duration.milliseconds(50)

    enum Visibility: Sendable {
        case hidden, visible
    }

    func hide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        await change(application, to: .hidden)
    }

    func unhide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        await change(application, to: .visible)
    }

    func connectedDisplays() async -> [DisplayIdentifier] {
        await MainActor.run { NSScreen.screens.compactMap(DisplayIdentifierMapping.identifier(of:)) }
    }

    /// Sets the image on the current Space of `display`, with empty options (the call S2 verified).
    ///
    /// - Throws: ``WorkspaceError/imageNotFound(fileName:)`` or ``WorkspaceError/displayNotFound(_:)`` before the
    ///   system is asked, or the error of `NSWorkspace.setDesktopImageURL(_:for:options:)`.
    func setDesktopImage(_ image: URL, on display: DisplayIdentifier) async throws {
        guard FileManager.default.fileExists(atPath: image.path(percentEncoded: false)) else {
            throw WorkspaceError.imageNotFound(fileName: image.lastPathComponent)
        }
        try await MainActor.run {
            guard let screen = DisplayIdentifierMapping.screen(for: display) else {
                throw WorkspaceError.displayNotFound(display)
            }
            try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [:])
        }
    }

    /// The outcome for the observed `isHidden` of every instance: no instance, every instance in the wanted state, or
    /// nil while some instance is not there yet.
    static func visibilityChange(observedHidden: [Bool], wanted: Visibility) -> ApplicationVisibilityChange? {
        guard !observedHidden.isEmpty else {
            return .notRunning
        }
        return observedHidden.allSatisfy { $0 == (wanted == .hidden) } ? .changed : nil
    }

    private func change(_ application: BundleIdentifier, to wanted: Visibility) async -> ApplicationVisibilityChange {
        let requested = await MainActor.run { Self.request(application, wanted) }
        guard requested else {
            return .notRunning
        }
        let clock = ContinuousClock()
        let deadline = clock.now + Self.visibilityTimeout
        while true {
            let observed = await MainActor.run { Self.instances(of: application).map(\.isHidden) }
            if let outcome = Self.visibilityChange(observedHidden: observed, wanted: wanted) {
                return outcome
            }
            guard clock.now < deadline else {
                return .refused
            }
            // A cancelled pause only shortens the watch; the next look decides.
            try? await Task.sleep(for: Self.visibilityPollInterval)
        }
    }

    /// Asks every instance; returns whether there was one. The `Bool` each request returns is not reliable.
    @MainActor
    private static func request(_ application: BundleIdentifier, _ wanted: Visibility) -> Bool {
        let instances = instances(of: application)
        for instance in instances {
            switch wanted {
            case .hidden: _ = instance.hide()
            case .visible: _ = instance.unhide()
            }
        }
        return !instances.isEmpty
    }

    @MainActor
    private static func instances(of application: BundleIdentifier) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: application.rawValue)
    }

    @MainActor
    private static func regularApplications() -> [RunningApplication] {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let this = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.activationPolicy == .regular, let identifier = bundleIdentifier(of: application) else {
                return nil
            }
            return RunningApplication(
                bundleIdentifier: identifier,
                isHidden: application.isHidden,
                isFrontmost: application.processIdentifier == frontmost,
                isThisApplication: application.processIdentifier == this,
            )
        }
    }

    @MainActor
    private static func bundleIdentifier(of application: NSRunningApplication) -> BundleIdentifier? {
        guard let rawValue = application.bundleIdentifier else {
            return nil
        }
        // An identifier that fails validation is skipped by contract (WorkspaceAdapter); the error adds nothing.
        return try? BundleIdentifier(rawValue)
    }
}
