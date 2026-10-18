import AppKit
import ModeKit

/// The real ``WorkspaceAdapter``: `NSWorkspace`, `NSRunningApplication` and `NSScreen` (ADR-036, ADR-038, ADR-040).
///
/// Every AppKit call hops to the main actor inside the async method. Hiding and unhiding are requests: `changed`
/// means at least one instance accepted, not that the effect was observed. `setDesktopImage` changes the current Space
/// of one display only (S2).
///
/// Threading: a value type; methods may be called from any context.
struct AppKitWorkspaceAdapter: WorkspaceAdapter {
    func runningApplications() async -> [RunningApplication] {
        await MainActor.run { Self.regularApplications() }
    }

    func hide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        await MainActor.run { Self.requestOnEveryInstance(of: application) { $0.hide() } }
    }

    func unhide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        await MainActor.run { Self.requestOnEveryInstance(of: application) { $0.unhide() } }
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

    /// The outcome of asking every instance: none running, any accepted, or all refused.
    static func visibilityChange(fromRequestResults results: [Bool]) -> ApplicationVisibilityChange {
        if results.isEmpty {
            return .notRunning
        }
        return results.contains(true) ? .changed : .refused
    }

    @MainActor
    private static func requestOnEveryInstance(
        of application: BundleIdentifier,
        _ request: (NSRunningApplication) -> Bool,
    ) -> ApplicationVisibilityChange {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: application.rawValue)
        return visibilityChange(fromRequestResults: instances.map(request))
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
