/// A regular (Dock-visible) application running in the user's session, as ``WorkspaceAdapter`` reports it.
public struct RunningApplication: Hashable, Sendable {
    /// The application's bundle identifier.
    public let bundleIdentifier: BundleIdentifier
    /// Whether the application is hidden (Hide in its application menu).
    public let isHidden: Bool
    /// Whether the application is the active one, receiving keyboard input.
    public let isFrontmost: Bool
    /// Whether the application is the one running this code.
    public let isThisApplication: Bool

    /// Creates a description of a running application.
    public init(bundleIdentifier: BundleIdentifier, isHidden: Bool, isFrontmost: Bool, isThisApplication: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.isHidden = isHidden
        self.isFrontmost = isFrontmost
        self.isThisApplication = isThisApplication
    }
}
