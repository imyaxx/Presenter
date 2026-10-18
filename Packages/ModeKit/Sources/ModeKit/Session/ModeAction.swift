/// One system change a profile step makes: capture the current state, apply the change, and restore.
///
/// Rules (docs/01-architecture.md): `capture` reads only; `apply` is safe to repeat without corrupting the
/// snapshot; restore is conditional (ADR-008); one action failing never blocks the others.
public protocol ModeAction: ActionRestorer {
    /// Reads the current system state without changing anything.
    ///
    /// - Throws: Any error of the underlying mechanism; activation stops before anything is applied.
    func capture() async throws -> Snapshot

    /// Applies the change and returns what was set.
    ///
    /// - Throws: Any error of the underlying mechanism; activation rolls back.
    func apply() async throws -> AppliedState
}
