import Foundation

/// Why the controller is degraded and needs ``SessionController/retryRestore()`` or a user decision.
public enum DegradedReason: Equatable, Sendable {
    /// Some actions could not be restored; their records are kept in `session.json`.
    case restoreFailed(sessionID: UUID, profileName: String, failures: [ActionFailure])
    /// `session.json` is corrupted or newer than this build; it is left untouched.
    case unreadableSessionFile(StoreError)
}
