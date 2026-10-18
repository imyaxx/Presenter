import Foundation
import ModeKit
import Testing

@testable import PresenterApp

struct SessionLogMessageTests {
    private static let sessionID = UUID(uuidString: "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21") ?? UUID()
    private static let secret = "SECRET /Users/someone/Library/session.json"
    private static let profileName = "Private Profile Name"
    private static let failure = ActionFailure(identifier: .dock, reason: secret)
    private static let storeError = StoreError.ioFailure(fileName: "session.json", reason: secret)
    private static let report = RestoreReport(
        restored: [.wallpaper],
        skippedBecauseChangedByUser: [.menuBar],
        failed: [failure],
    )

    static let everyEvent: [SessionEvent] = [
        .stateChanged(
            previous: .idle,
            current: .applying(sessionID: sessionID, profileName: profileName),
            sessionID: sessionID,
        ),
        .stateChanged(
            previous: .restoring(sessionID: sessionID, profileName: profileName),
            current: .degraded(.restoreFailed(sessionID: sessionID, profileName: profileName, failures: [failure])),
            sessionID: sessionID,
        ),
        .stateChanged(
            previous: .active(
                ActiveSession(sessionID: sessionID, profileID: UUID(), profileName: profileName, startedAt: Date())),
            current: .rollingBack(sessionID: sessionID, profileName: profileName),
            sessionID: sessionID,
        ),
        .stateChanged(previous: .idle, current: .degraded(.unreadableSessionFile(storeError)), sessionID: nil),
        .triggerIgnored(.activate, state: .applying(sessionID: sessionID, profileName: profileName)),
        .actionCaptured(sessionID: sessionID, .dock),
        .actionApplied(sessionID: sessionID, .menuBar),
        .actionRestored(sessionID: sessionID, .hideApps),
        .actionSkippedBecauseChangedByUser(sessionID: sessionID, .wallpaper),
        .actionFailed(sessionID: sessionID, .desktopIcons, phase: .apply, reason: secret),
        .recoveryStarted,
        .recoveryFinished(.nothingToRecover),
        .recoveryFinished(.restored(report)),
        .recoveryFinished(.partiallyRestored(report)),
        .recoveryFinished(.blocked(storeError)),
        .recoveryFinished(.alreadyAttempted),
        .sessionFileFailed(sessionID: sessionID, .write, storeError),
    ]

    @Test(arguments: everyEvent)
    func noReasonOrProfileNameIsInThePublicText(event: SessionEvent) {
        let message = SessionLogMessage(event)

        #expect(!message.publicText.isEmpty)
        #expect(!message.publicText.contains("SECRET"))
        #expect(!message.publicText.contains("/Users/"))
        #expect(!message.publicText.contains(Self.profileName))
    }

    @Test
    func aFailedActionIsAnErrorWithItsReasonPrivate() {
        let message = SessionLogMessage(
            .actionFailed(sessionID: Self.sessionID, .dock, phase: .restore, reason: Self.secret))

        #expect(
            message
                == SessionLogMessage(
                    level: .error,
                    publicText: "action dock failed in restore session=6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21",
                    privateDetail: Self.secret,
                ))
    }

    @Test
    func aStateChangeIsInfoWithStateNamesAndTheSessionID() {
        let event = SessionEvent.stateChanged(
            previous: .idle,
            current: .applying(sessionID: Self.sessionID, profileName: Self.profileName),
            sessionID: Self.sessionID,
        )

        #expect(
            SessionLogMessage(event)
                == SessionLogMessage(
                    level: .info,
                    publicText: "state idle -> applying session=6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21",
                ))
    }

    @Test
    func aPartialRecoveryListsIdentifiersPubliclyAndReasonsPrivately() {
        let message = SessionLogMessage(.recoveryFinished(.partiallyRestored(Self.report)))

        #expect(message.level == .error)
        #expect(
            message.publicText == "recovery finished partially, restored [wallpaper] skipped [menuBar] failed [dock]")
        #expect(message.privateDetail == "dock: \(Self.secret)")
    }

    @Test(arguments: everyEvent)
    func theLoggerAcceptsEveryEvent(event: SessionEvent) {
        OSSessionLogger(subsystem: "dev.imyaxx.presenter.tests").log(event)
    }
}
