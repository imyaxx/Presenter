/// A failure of a session controller trigger. Per-action restore failures are reported, not thrown.
public enum SessionError: Error, Equatable, Sendable {
    /// The profile breaks a rule; nothing was touched.
    case invalidProfile(ProfileValidationError)
    /// ``SessionController/recoverIfNeeded()`` has not finished yet.
    case recoveryNotRun
    /// An action could not be built or captured; nothing was applied and no file was written.
    case captureFailed(ActionFailure)
    /// `session.json` could not be read, written or removed.
    case sessionStoreFailed(StoreError)
    /// Applying failed; `rollback` reports how the applied actions were restored.
    case applyFailed(ActionFailure, rollback: RestoreReport)
}
