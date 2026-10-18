import Foundation

/// A process to run: an executable and its argument vector, never a shell command string.
public struct ProcessCommand: Hashable, Sendable {
    /// The absolute URL of the executable.
    public let executableURL: URL
    /// The arguments, passed as an argv array.
    public let arguments: [String]
    /// The longest the runner waits before it terminates the process and throws ``ProcessError/timedOut(_:)``.
    public let timeout: Duration

    /// Creates a command.
    public init(executableURL: URL, arguments: [String], timeout: Duration) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
    }
}
