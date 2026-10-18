import Foundation

/// The persisted state of one action in a session: what was captured before applying, and what was applied.
///
/// Snapshots differ per action, so both are stored as opaque encoded `Data` (base64 in JSON); the action that
/// produced them decodes them. JSON keys: `identifier`, `snapshotData`, and `appliedData` (omitted while nil).
public struct ActionRecord: Codable, Hashable, Sendable {
    /// The action this record belongs to.
    public let identifier: ActionIdentifier
    /// The encoded snapshot captured before the action was applied.
    public let snapshotData: Data
    /// The encoded state the action applied; nil until the action has been applied.
    public let appliedData: Data?

    /// Creates a record.
    public init(identifier: ActionIdentifier, snapshotData: Data, appliedData: Data?) {
        self.identifier = identifier
        self.snapshotData = snapshotData
        self.appliedData = appliedData
    }
}
