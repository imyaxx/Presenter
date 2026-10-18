/// What a restore pass did for each action, in restore order (the reverse of apply order).
public struct RestoreReport: Equatable, Sendable {
    /// Actions written back to their snapshot.
    public let restored: [ActionIdentifier]
    /// Actions left alone because the user changed the value meanwhile (ADR-008).
    public let skippedBecauseChangedByUser: [ActionIdentifier]
    /// Actions whose restore failed; their records stay in `session.json`.
    public let failed: [ActionFailure]

    /// Creates a report.
    public init(
        restored: [ActionIdentifier],
        skippedBecauseChangedByUser: [ActionIdentifier],
        failed: [ActionFailure],
    ) {
        self.restored = restored
        self.skippedBecauseChangedByUser = skippedBecauseChangedByUser
        self.failed = failed
    }
}
