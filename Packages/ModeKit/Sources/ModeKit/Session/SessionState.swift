import Foundation

/// The session controller's state. See the state machine in docs/01-architecture.md.
public enum SessionState: Equatable, Sendable {
    /// No session; ready to activate.
    case idle
    /// Capturing and applying a profile's actions.
    case applying(sessionID: UUID, profileName: String)
    /// Every action is applied.
    case active(ActiveSession)
    /// Restoring after deactivate, the auto-exit timer, recovery or a retry.
    case restoring(sessionID: UUID, profileName: String)
    /// Restoring the actions of a failed activation.
    case rollingBack(sessionID: UUID, profileName: String)
    /// Restore could not finish; see the reason.
    case degraded(DegradedReason)

    var sessionID: UUID? {
        switch self {
        case .idle: nil
        case .applying(let sessionID, _), .restoring(let sessionID, _), .rollingBack(let sessionID, _): sessionID
        case .active(let session): session.sessionID
        case .degraded(.restoreFailed(let sessionID, _, _)): sessionID
        case .degraded(.unreadableSessionFile): nil
        }
    }
}
