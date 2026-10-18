import Foundation

/// A structured log event of the session controller. Every event that concerns a session carries its ID.
///
/// `reason` strings are `String(describing:)` of errors and may contain file paths: loggers must treat them as
/// private.
public enum SessionEvent: Equatable, Sendable {
    /// A public trigger of the controller.
    public enum Trigger: Equatable, Sendable {
        case activate, deactivate, retryRestore, discardUnreadableSession, autoExitTimer
    }

    /// The step of an action that failed.
    public enum ActionPhase: Equatable, Sendable {
        case capture, apply, restore
    }

    /// An operation on `session.json`.
    public enum FileOperation: Equatable, Sendable {
        case write, remove
    }

    case stateChanged(previous: SessionState, current: SessionState, sessionID: UUID?)
    case triggerIgnored(Trigger, state: SessionState)
    case actionCaptured(sessionID: UUID, ActionIdentifier)
    case actionApplied(sessionID: UUID, ActionIdentifier)
    case actionRestored(sessionID: UUID, ActionIdentifier)
    case actionSkippedBecauseChangedByUser(sessionID: UUID, ActionIdentifier)
    case actionFailed(sessionID: UUID, ActionIdentifier, phase: ActionPhase, reason: String)
    case recoveryStarted
    case recoveryFinished(RecoveryOutcome)
    case sessionFileFailed(sessionID: UUID?, FileOperation, StoreError)
}
