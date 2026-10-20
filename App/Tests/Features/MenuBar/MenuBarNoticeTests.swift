import Foundation
import ModeKit
import Testing

@testable import PresenterApp

struct MenuBarNoticeTests {
    private static let failure = ActionFailure(identifier: .dock, reason: "Not authorized (-1743)")

    @Test(arguments: [
        (SessionError.captureFailed(failure), MenuBarNotice.activationFailed(.dock, .nothingChanged)),
        (
            .applyFailed(failure, rollback: MenuBarFixtures.report(restored: [.dock])),
            .activationFailed(.dock, .undone),
        ),
        (
            .applyFailed(failure, rollback: MenuBarFixtures.report(failed: [.desktopIcons])),
            .activationFailed(.dock, .partlyUndone),
        ),
        (.invalidProfile(.emptyName), .invalidProfile),
        (.recoveryNotRun, .notReady),
        (.sessionStoreFailed(.ioFailure(fileName: "session.json", reason: "x")), .sessionFileNotSaved),
    ])
    func activationFailuresMapByCaseAndPhase(error: SessionError, expected: MenuBarNotice) {
        #expect(MenuBarNotice.activationFailure(error) == expected)
    }

    @Test
    func aFailedDockActionMentionsTheAutomationPermission() {
        #expect(MenuBarNotice.activationFailed(.dock, .undone).mentionsAutomationPermission)
        #expect(!MenuBarNotice.activationFailed(.menuBar, .undone).mentionsAutomationPermission)
        #expect(!MenuBarNotice.invalidProfile.mentionsAutomationPermission)
    }

    @Test
    func aRestoreNamesTheActionsTheUserChanged() {
        #expect(MenuBarNotice.afterRestore(MenuBarFixtures.report(restored: [.dock])) == nil)
        #expect(
            MenuBarNotice.afterRestore(MenuBarFixtures.report(restored: [.dock], skipped: [.wallpaper]))
                == .keptUserChanges([.wallpaper]))
    }

    @Test
    func onlyARestoredRecoveryGivesANotice() {
        let restored = RecoveryOutcome.restored(MenuBarFixtures.report(restored: [.dock], skipped: [.menuBar]))

        #expect(MenuBarNotice.afterRecovery(restored) == .recoveredAfterInterruption(kept: [.menuBar]))
        #expect(MenuBarNotice.afterRecovery(.nothingToRecover) == nil)
        #expect(MenuBarNotice.afterRecovery(.partiallyRestored(MenuBarFixtures.report(failed: [.dock]))) == nil)
        #expect(MenuBarNotice.afterRecovery(.blocked(.corrupted(fileName: "session.json", reason: "x"))) == nil)
        #expect(MenuBarNotice.afterRecovery(.alreadyAttempted) == nil)
    }

    @Test(arguments: [
        (StoreError.corrupted(fileName: "profiles.json", reason: "x"), ProfilesProblem.corrupted),
        (.unsupportedSchemaVersion(found: 2, supported: 1), .newerVersion),
        (.ioFailure(fileName: "profiles.json", reason: "x"), .unreadable),
        (.invalidProfile(.emptyName), .corrupted),
        (.duplicateProfileID(MenuBarFixtures.sessionID), .corrupted),
        (.encodingFailed(fileName: "profiles.json", reason: "x"), .unreadable),
    ])
    func profileLoadFailuresMapByStoreErrorCase(error: StoreError, expected: ProfilesProblem) {
        #expect(ProfilesProblem(error) == expected)
    }

    @Test
    func anErrorOtherThanAStoreErrorIsUnreadable() {
        #expect(ProfilesProblem(CocoaError(.fileReadUnknown)) == .unreadable)
    }
}
