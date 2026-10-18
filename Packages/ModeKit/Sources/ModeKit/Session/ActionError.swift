/// A failure to build or decode an action, as opposed to a failure of the system change itself.
public enum ActionError: Error, Equatable, Sendable {
    /// No action or restorer is registered for the identifier.
    case unsupported(ActionIdentifier)
    /// A persisted snapshot or applied state cannot be decoded as the restorer's type.
    case undecodableRecord(ActionIdentifier, reason: String)
}
