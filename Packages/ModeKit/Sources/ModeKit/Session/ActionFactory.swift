/// Builds actions for profile steps and restorers for persisted records. Implemented by the composition root.
///
/// Threading: implementations are `Sendable`; methods may be called from any context.
public protocol ActionFactory: Sendable {
    /// Returns the action that performs `step`.
    ///
    /// - Throws: ``ActionError/unsupported(_:)`` when no action is registered for the step.
    func makeAction(for step: ProfileStep) throws -> any ModeAction

    /// Returns the restorer for records of `identifier`, without a profile.
    ///
    /// - Throws: ``ActionError/unsupported(_:)`` when no restorer is registered for the identifier.
    func makeRestorer(for identifier: ActionIdentifier) throws -> any ActionRestorer
}
