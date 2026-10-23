import Foundation
import ModeKit
import Testing

@testable import PresenterApp

struct MenuBarPresentationTests {
    private static let id = MenuBarFixtures.sessionID

    struct Case: Sendable, CustomTestStringConvertible {
        let state: SessionState
        let presentation: MenuBarPresentation
        let icon: MenuBarIconShape?
        let testDescription: String
    }

    static let restoreFailed = SessionState.degraded(
        .restoreFailed(sessionID: id, profileName: "Quick", failures: [ActionFailure(identifier: .dock, reason: "x")]))
    static let unreadable = SessionState.degraded(
        .unreadableSessionFile(.corrupted(fileName: "session.json", reason: "x")))

    static let cases = [
        Case(state: .idle, presentation: .idle, icon: .idle, testDescription: "idle"),
        Case(
            state: .applying(sessionID: id, profileName: "Quick"),
            presentation: .applying(profileName: "Quick"),
            icon: nil,
            testDescription: "applying",
        ),
        Case(
            state: .active(MenuBarFixtures.activeSession),
            presentation: .active(MenuBarFixtures.activeSession),
            icon: .active,
            testDescription: "active",
        ),
        Case(
            state: .restoring(sessionID: id, profileName: "Quick"),
            presentation: .restoring(profileName: "Quick"),
            icon: nil,
            testDescription: "restoring",
        ),
        Case(
            state: .rollingBack(sessionID: id, profileName: "Quick"),
            presentation: .rollingBack(profileName: "Quick"),
            icon: nil,
            testDescription: "rolling back",
        ),
        Case(
            state: restoreFailed,
            presentation: .restoreFailed(profileName: "Quick", actions: [.dock]),
            icon: .needsAttention,
            testDescription: "degraded, restore failed",
        ),
        Case(
            state: unreadable,
            presentation: .unreadableSessionFile,
            icon: .needsAttention,
            testDescription: "degraded, unreadable file",
        ),
    ]

    @Test(arguments: cases)
    func everyStateMapsToAPresentationAndIcon(entry: Case) {
        let presentation = MenuBarPresentation(entry.state)

        #expect(presentation == entry.presentation)
        #expect(presentation.iconShape == entry.icon)
    }

    @Test
    func eachPresentationAcceptsOnlyItsTriggers() {
        let active = MenuBarPresentation.active(MenuBarFixtures.activeSession)
        let failed = MenuBarPresentation.restoreFailed(profileName: "Quick", actions: [.dock])
        let others: [MenuBarPresentation] = [
            .unavailable, .recoveringAtLaunch, .applying(profileName: "Q"), .restoring(profileName: "Q"),
            .rollingBack(profileName: "Q"),
        ]

        #expect(MenuBarPresentation.idle.acceptsActivation)
        #expect(active.acceptsStop && !active.acceptsActivation)
        #expect(failed.acceptsRetry && !failed.acceptsDiscard)
        #expect(MenuBarPresentation.unreadableSessionFile.acceptsRetry)
        #expect(MenuBarPresentation.unreadableSessionFile.acceptsDiscard)
        for presentation in others {
            #expect(!presentation.acceptsActivation && !presentation.acceptsStop)
            #expect(!presentation.acceptsRetry && !presentation.acceptsDiscard)
        }
    }

    @Test
    func theUnavailableAndLaunchStatesHaveTheirIcons() {
        #expect(MenuBarPresentation.unavailable.iconShape == .needsAttention)
        #expect(MenuBarPresentation.recoveringAtLaunch.iconShape == .idle)
        #expect(
            [MenuBarIconShape.idle, .active, .needsAttention].map(\.symbolName) == [
                "display", "eye.slash", "exclamationmark.triangle",
            ])
    }
}
