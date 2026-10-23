import ModeKit

/// What the menu bar needs from the session controller: its state and its triggers (ADR-043).
///
/// `SessionController` conforms in `Application/`; tests use a fake. Threading: implementations are `Sendable`.
protocol SessionControlling: Sendable {
    /// The current state.
    var state: SessionState { get async }

    /// The current state first, then every change.
    func stateUpdates() async -> AsyncStream<SessionState>

    func recoverIfNeeded() async -> RecoveryOutcome
    func activate(_ profile: Profile) async throws(SessionError) -> TriggerResult<ActiveSession>
    func deactivate() async throws(SessionError) -> TriggerResult<RestoreReport>
    func retryRestore() async -> TriggerResult<RecoveryOutcome>
    func discardUnreadableSession() async throws(SessionError) -> TriggerResult<Void>
}
