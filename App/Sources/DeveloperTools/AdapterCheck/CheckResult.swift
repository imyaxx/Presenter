#if DEBUG
import Foundation

/// The JSON file every command writes, because `open -W` does not return the program's exit code (ADR-042).
///
/// `{"status": "ok" | "failed", "command": ..., "error": ..., "details": ...}`, pretty-printed with sorted keys.
struct CheckResult<Details: Encodable & Sendable>: Encodable, Sendable {
    enum Status: String, Encodable, Sendable {
        case succeeded = "ok"
        case failed
    }

    let status: Status
    let command: String
    let error: String?
    let details: Details?

    static func succeeded(_ command: String, details: Details) -> CheckResult {
        CheckResult(status: .succeeded, command: command, error: nil, details: details)
    }

    static func failed(_ command: String, error: String, details: Details? = nil) -> CheckResult {
        CheckResult(status: .failed, command: command, error: error, details: details)
    }

    /// Writes the result atomically, creating the parent directory.
    ///
    /// - Throws: An encoding or file-system error.
    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true, )
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// The details of a command that has nothing to report beyond its status.
struct NoDetails: Encodable, Equatable, Sendable {}
#endif
