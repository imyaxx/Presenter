/// What a restore did.
public enum RestoreOutcome: Equatable, Sendable {
    /// The captured value was written back.
    case restored
    /// The current value is no longer what this app applied, so the user changed it meanwhile and it is kept
    /// (ADR-008). After an interrupted restore this can also mean the value was already restored.
    case skippedBecauseChangedByUser
}
