import Foundation
import ModeKit

/// Builds session records with overridable fields for tests. `startedAt` has whole seconds, as stored.
struct SessionRecordBuilder {
    var sessionID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001") ?? UUID()
    var profileID = UUID(uuidString: "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21") ?? UUID()
    var profileName = "Screen share"
    var startedAt = Date(timeIntervalSince1970: 1_792_238_400)
    var actions: [ActionRecord] = [
        ActionRecord(identifier: .dock, snapshotData: Data("{\"autohide\":true}".utf8), appliedData: nil)
    ]

    func build() -> SessionRecord {
        SessionRecord(
            sessionID: sessionID,
            profileID: profileID,
            profileName: profileName,
            startedAt: startedAt,
            actions: actions,
        )
    }
}
