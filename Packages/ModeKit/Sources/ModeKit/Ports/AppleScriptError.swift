/// A failure of an ``AppleScriptRunner``.
public enum AppleScriptError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Automation permission for the target application is denied or missing (error -1743).
    case notAuthorized
    /// The Apple event timed out, for example because the permission prompt was left unanswered (error -1712).
    case timedOut
    /// Any other script error.
    case failed(code: Int, message: String)

    private static let notAuthorizedCode = -1743
    private static let timedOutCode = -1712

    /// Maps an AppleScript error number and message, as reported by the system, to a case.
    public init(code: Int, message: String) {
        switch code {
        case Self.notAuthorizedCode: self = .notAuthorized
        case Self.timedOutCode: self = .timedOut
        default: self = .failed(code: code, message: message)
        }
    }

    public var description: String {
        switch self {
        case .notAuthorized: "Not authorized to send Apple events (-1743)"
        case .timedOut: "Apple event timed out (-1712)"
        case .failed(let code, let message): "AppleScript error \(code): \(message)"
        }
    }
}
