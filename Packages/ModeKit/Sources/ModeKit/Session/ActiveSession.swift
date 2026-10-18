import Foundation

/// The identity of a running session.
public struct ActiveSession: Equatable, Sendable {
    /// Identifies this activation in logs and in `session.json`.
    public let sessionID: UUID
    /// The activated profile.
    public let profileID: UUID
    /// The activated profile's name at activation.
    public let profileName: String
    /// When activation started.
    public let startedAt: Date

    /// Creates a session identity.
    public init(sessionID: UUID, profileID: UUID, profileName: String, startedAt: Date) {
        self.sessionID = sessionID
        self.profileID = profileID
        self.profileName = profileName
        self.startedAt = startedAt
    }
}

extension ActiveSession {
    init(_ record: SessionRecord) {
        self.init(
            sessionID: record.sessionID,
            profileID: record.profileID,
            profileName: record.profileName,
            startedAt: record.startedAt,
        )
    }

    func record(with actions: [ActionRecord]) -> SessionRecord {
        SessionRecord(
            sessionID: sessionID,
            profileID: profileID,
            profileName: profileName,
            startedAt: startedAt,
            actions: actions,
        )
    }
}
