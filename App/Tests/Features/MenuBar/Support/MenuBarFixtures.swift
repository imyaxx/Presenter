import Foundation
import ModeKit

/// Profiles and sessions used by the menu bar tests.
enum MenuBarFixtures {
    static let sessionID = UUID(uuidString: "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21") ?? UUID()
    static let quick = Profile(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000001") ?? UUID(),
        name: "Quick",
        steps: [.hideDesktopIcons, .hideMenuBar],
        autoExit: nil,
    )
    static let full = Profile(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000002") ?? UUID(),
        name: "Full",
        steps: [.hideDesktopIcons, .hideDock, .hideMenuBar],
        autoExit: nil,
    )
    static let activeSession = ActiveSession(
        sessionID: sessionID,
        profileID: quick.id,
        profileName: quick.name,
        startedAt: Date(timeIntervalSince1970: 1_800_000_000),
    )

    static func report(
        restored: [ActionIdentifier] = [],
        skipped: [ActionIdentifier] = [],
        failed: [ActionIdentifier] = [],
    ) -> RestoreReport {
        RestoreReport(
            restored: restored,
            skippedBecauseChangedByUser: skipped,
            failed: failed.map { ActionFailure(identifier: $0, reason: "scripted") },
        )
    }
}
