import AppKit

/// Keeps a second launch of the app from running next to the first, which would race on `session.json` (ADR-043).
///
/// Threading: main actor, because it activates another application.
@MainActor
struct NSRunningApplicationInstanceGuard {
    let bundleIdentifier: String

    /// The process identifier of another instance among `running`, never the current process.
    nonisolated static func otherInstance(among running: [pid_t], current: pid_t) -> pid_t? {
        running.first { $0 != current }
    }

    /// Activates another running instance of this bundle identifier and returns whether one exists.
    func activateOtherInstance() -> Bool {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let current = NSRunningApplication.current.processIdentifier
        guard let other = Self.otherInstance(among: instances.map(\.processIdentifier), current: current),
            let application = instances.first(where: { $0.processIdentifier == other })
        else {
            return false
        }
        application.activate()
        return true
    }
}
