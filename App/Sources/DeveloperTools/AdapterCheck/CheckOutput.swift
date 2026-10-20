#if DEBUG
import Foundation

/// Where the tool's JSON event lines go: standard output in a real run, a closure in tests.
///
/// The only place in the app that writes to standard output (ADR-042). The adapter check script redirects it to a
/// file under the check directory; it may contain local data and is never committed.
struct CheckOutput: Sendable {
    private let writeLine: @Sendable (String) -> Void

    init(writeLine: @escaping @Sendable (String) -> Void) {
        self.writeLine = writeLine
    }

    /// Writes each line to the process's standard output.
    static let standardOutput = CheckOutput { line in
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// Writes `value` as one line of compact JSON with sorted keys. A value that cannot be encoded is reported as a
    /// line of its own, so no event is dropped silently.
    func emit(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let line = try encoder.encode(value)
            // JSONEncoder always produces UTF-8, so the fallback is never used.
            writeLine(String(bytes: line, encoding: .utf8) ?? "")
        } catch {
            writeLine("{\"type\":\"output-error\",\"reason\":\"\(error)\"}")
        }
    }
}
#endif
