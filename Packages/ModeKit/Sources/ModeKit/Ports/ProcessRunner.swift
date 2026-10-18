/// Runs a process from an argv array and waits for it to end.
///
/// The implementation enforces ``ProcessCommand/timeout``. Threading: implementations are `Sendable`.
public protocol ProcessRunner: Sendable {
    /// Runs the command and returns its exit code. A nonzero exit is returned, not thrown.
    ///
    /// - Throws: ``ProcessError/timedOut(_:)`` or ``ProcessError/launchFailed(reason:)``.
    func run(_ command: ProcessCommand) async throws -> ProcessResult
}
