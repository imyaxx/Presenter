/// The result of asking ``WorkspaceAdapter`` to hide or unhide an application.
public enum ApplicationVisibilityChange: Equatable, Sendable {
    /// The request was accepted. Hiding is asynchronous in AppKit, so the effect may not be visible yet; this is
    /// not an observation of the effect.
    case changed
    /// No running application has this bundle identifier.
    case notRunning
    /// The application is running but did not accept the request.
    case refused
}
