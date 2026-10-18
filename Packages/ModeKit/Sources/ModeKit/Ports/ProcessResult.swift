/// How a process ended.
public struct ProcessResult: Equatable, Sendable {
    /// The exit code. A nonzero exit is a result, not an error; the caller decides what it means.
    public let exitCode: Int32

    /// Creates a result.
    public init(exitCode: Int32) {
        self.exitCode = exitCode
    }
}
