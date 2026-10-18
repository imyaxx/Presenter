/// One action that failed, with a non-localized diagnostic. The UI maps it by identifier and phase.
public struct ActionFailure: Equatable, Sendable {
    /// The failed action.
    public let identifier: ActionIdentifier
    /// `String(describing:)` of the error. May contain a path; treat it as private when logging.
    public let reason: String

    /// Creates a failure.
    public init(identifier: ActionIdentifier, reason: String) {
        self.identifier = identifier
        self.reason = reason
    }
}

extension ActionFailure {
    init(identifier: ActionIdentifier, error: any Error) {
        self.init(identifier: identifier, reason: String(describing: error))
    }
}
