/// Receives the session controller's structured events. ModeKit does not import `os`; the real implementation
/// (`os.Logger` with privacy annotations) belongs to the platform adapters.
///
/// Threading: implementations are `Sendable`; `log` is called on the controller's actor and must not block.
public protocol SessionLogger: Sendable {
    /// Records one event. `reason` strings may contain paths and must be logged as private.
    func log(_ event: SessionEvent)
}
