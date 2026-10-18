import Foundation

/// Everything needed to restore an active session after a crash or reboot, written before any system change.
///
/// `startedAt` is stored as ISO 8601 with whole-second precision. JSON keys: `sessionID`, `profileID`,
/// `profileName`, `startedAt`, `actions`.
public struct SessionRecord: Codable, Hashable, Sendable {
    /// Identifies this activation in logs.
    public let sessionID: UUID
    /// The profile that was activated.
    public let profileID: UUID
    /// The profile's name at activation, for messages after the profile changed or was deleted.
    public let profileName: String
    /// When the session started.
    public let startedAt: Date
    /// One record per action, in apply order.
    public let actions: [ActionRecord]

    /// Creates a record.
    public init(sessionID: UUID, profileID: UUID, profileName: String, startedAt: Date, actions: [ActionRecord]) {
        self.sessionID = sessionID
        self.profileID = profileID
        self.profileName = profileName
        self.startedAt = startedAt
        self.actions = actions
    }
}
