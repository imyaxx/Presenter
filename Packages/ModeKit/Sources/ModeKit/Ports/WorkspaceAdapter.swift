import Foundation

/// Lists running applications and hides or unhides them; lists displays and sets their desktop image.
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

    /// The displays connected now, by display UUID.
    func connectedDisplays() async -> [DisplayIdentifier]

    /// Sets the desktop image of the **current Space** of `display` only; other Spaces keep their wallpaper (S2).
    ///
    /// The wallpaper agent persists the change to the wallpaper store asynchronously.
    /// - Throws: An error when the image file is missing or the display is gone.
    func setDesktopImage(_ image: URL, on display: DisplayIdentifier) async throws
}
