/// A failure of a ``ProcessRunner``.
public enum ProcessError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The process did not end within its timeout and was terminated.
    case timedOut(Duration)
    /// The process could not be started.
    case launchFailed(reason: String)

    public var description: String {
        switch self {
        case .timedOut(let timeout): "Process timed out after \(timeout)"
        case .launchFailed(let reason): "Process could not be launched: \(reason)"
        }
    }
}
