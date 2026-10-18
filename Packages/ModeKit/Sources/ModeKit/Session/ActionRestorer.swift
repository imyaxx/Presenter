/// Restores one action from a persisted snapshot. Needs no profile, so crash recovery works after the profile
/// was edited or deleted (ADR-032).
///
/// Threading: implementations are `Sendable`; the session controller calls one method at a time per action.
public protocol ActionRestorer: Sendable {
    /// What ``ModeAction/capture()`` records before anything changes.
    associatedtype Snapshot: Codable & Sendable
    /// What ``ModeAction/apply()`` set, used to detect a change by the user (ADR-008).
    associatedtype AppliedState: Codable & Sendable

    /// The action this restorer belongs to.
    var identifier: ActionIdentifier { get }

    /// Returns the system to `snapshot`.
    ///
    /// When `applied` is non-nil the restore is conditional: if the current value no longer equals `applied`, the
    /// user changed it meanwhile; leave it and return ``RestoreOutcome/skippedBecauseChangedByUser``.
    /// `applied` is nil when the apply was interrupted (crash, or a failure while applying this action): the system
    /// may be partly changed and the applied value is unknown. Then restore unconditionally to `snapshot`.
    ///
    /// - Throws: Any error of the underlying mechanism; the controller records it as a failure for this action
    ///   and still restores the others.
    func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome
}
