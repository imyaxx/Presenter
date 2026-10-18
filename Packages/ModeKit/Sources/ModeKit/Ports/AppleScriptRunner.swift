/// Runs an AppleScript and waits for it to finish. The result is not returned: no action needs it.
///
/// The implementation enforces the timeout and maps errors to ``AppleScriptError``. Threading: implementations are
/// `Sendable`.
public protocol AppleScriptRunner: Sendable {
    /// Runs the script.
    ///
    /// - Throws: ``AppleScriptError``.
    func run(_ script: AppleScript, timeout: Duration) async throws
}
