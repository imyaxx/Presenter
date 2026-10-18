/// Lists running applications and hides or unhides them.
///
/// In-process calls with no timeout by design, like ``DefaultsStore``: the implementation must not block on another
/// process (hiding is a request, not a wait for the effect). Threading: implementations are `Sendable`; methods may
/// be called from any context.
public protocol WorkspaceAdapter: Sendable {
    /// Regular (Dock-visible) applications only. The adapter skips applications whose bundle identifier is not a valid
    /// `BundleIdentifier`. Several instances of one bundle identifier are reported as separate entries.
    func runningApplications() async -> [RunningApplication]

    /// Asks every running instance of the application to hide.
    ///
    /// - Returns: ``ApplicationVisibilityChange/changed`` when the request was accepted, not when the effect was seen.
    func hide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange

    /// Asks every running instance of the application to unhide.
    ///
    /// - Returns: ``ApplicationVisibilityChange/changed`` when the request was accepted, not when the effect was seen.
    func unhide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange
}
