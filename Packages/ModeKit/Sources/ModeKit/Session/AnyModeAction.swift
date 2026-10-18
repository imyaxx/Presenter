import Foundation

/// A type-erased ``ModeAction`` whose snapshot and applied state travel as encoded `Data`.
struct AnyModeAction: Sendable {
    let identifier: ActionIdentifier
    let restorer: AnyActionRestorer
    private let captureSnapshot: @Sendable () async throws -> Data
    private let applyChange: @Sendable () async throws -> Data

    init<Action: ModeAction>(_ action: Action) {
        identifier = action.identifier
        restorer = AnyActionRestorer(action)
        captureSnapshot = { try PersistenceCoding.makeEncoder().encode(try await action.capture()) }
        applyChange = { try PersistenceCoding.makeEncoder().encode(try await action.apply()) }
    }

    /// Captures and returns the encoded snapshot.
    ///
    /// - Throws: The action's error, or an encoding error.
    func capture() async throws -> Data {
        try await captureSnapshot()
    }

    /// Applies and returns the encoded applied state.
    ///
    /// - Throws: The action's error, or an encoding error.
    func apply() async throws -> Data {
        try await applyChange()
    }
}
