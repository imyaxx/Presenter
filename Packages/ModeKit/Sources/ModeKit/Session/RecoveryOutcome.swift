/// The result of crash recovery or of a retry.
public enum RecoveryOutcome: Equatable, Sendable {
    /// No `session.json` exists.
    case nothingToRecover
    /// Every action was restored or skipped; `session.json` is gone.
    case restored(RestoreReport)
    /// Some actions failed; their records stay in `session.json` and the controller is degraded.
    case partiallyRestored(RestoreReport)
    /// `session.json` is corrupted or newer; it is untouched and the controller is degraded.
    case blocked(StoreError)
    /// Recovery already ran or is running.
    case alreadyAttempted
}
