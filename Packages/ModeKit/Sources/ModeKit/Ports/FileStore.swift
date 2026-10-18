import Foundation

/// Reads, atomically writes and removes whole files. The persistence port of ModeKit.
///
/// Local file I/O has no timeout by design: it is not an external wait (docs/03-code-standards.md asks for
/// timeouts on processes, AppleScript and other external waits).
///
/// Threading: implementations are `Sendable` and may be called from any context.
public protocol FileStore: Sendable {
    /// Returns the file's contents, or nil when no file exists at `url`.
    ///
    /// - Throws: An I/O error for any failure other than the file being absent.
    func read(_ url: URL) async throws -> Data?

    /// Replaces the file at `url` with `data` atomically, creating the parent directory if needed.
    ///
    /// After a failure the previous file, if any, is unchanged.
    /// - Throws: An I/O error when any step fails.
    func write(_ data: Data, to url: URL) async throws

    /// Removes the file at `url`. Removing a file that does not exist succeeds.
    ///
    /// - Throws: An I/O error for any failure other than the file being absent.
    func remove(_ url: URL) async throws
}
