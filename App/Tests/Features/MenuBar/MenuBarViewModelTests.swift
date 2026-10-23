import Foundation
import ModeKit
import Testing

@testable import PresenterApp

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MenuBarViewModelTests {
    private let id = MenuBarFixtures.sessionID
    private let restoreFailed = MenuBarPresentationTests.restoreFailed
    private let unreadable = MenuBarPresentationTests.unreadable

    @Test
    func untilRecoveryFinishesTheMenuShowsRestoringAndOffersNoTrigger() async {
        let harness = MenuBarTestHarness()
        await harness.start(recovering: .skip)
        await harness.session.emit(.idle)

        #expect(harness.model.presentation == .recoveringAtLaunch)
        #expect(!harness.model.canActivate)
        await harness.model.activate(MenuBarFixtures.quick)
        #expect(await harness.session.calls.isEmpty)
        harness.stop()
    }

    @Test
    func afterRecoveryTheStateAndTheProfilesAreShown() async {
        let harness = MenuBarTestHarness()

        await harness.start()

        #expect(await harness.session.calls == ["recover"])
        #expect(await harness.eventually { harness.model.presentation == .idle })
        #expect(harness.model.profiles == [MenuBarFixtures.quick, MenuBarFixtures.full])
        #expect(harness.model.canActivate)
        harness.stop()
    }

    @Test
    func aRecoveryThatRestoredSomethingLeavesANotice() async {
        let harness = MenuBarTestHarness()
        await harness.session.setRecoveryOutcome(
            .restored(MenuBarFixtures.report(restored: [.dock], skipped: [.wallpaper])))

        await harness.start()

        #expect(harness.model.notice == .recoveredAfterInterruption(kept: [.wallpaper]))
        harness.stop()
    }

    @Test
    func aPartialOrBlockedRecoveryShowsNeedsAttentionWithoutANotice() async {
        let harness = MenuBarTestHarness(state: restoreFailed)
        await harness.session.setRecoveryOutcome(.partiallyRestored(MenuBarFixtures.report(failed: [.dock])))

        await harness.start()

        #expect(
            await harness.eventually {
                harness.model.presentation == .restoreFailed(profileName: "Quick", actions: [.dock])
            })
        #expect(harness.model.notice == nil)
        #expect(harness.model.iconShape == .needsAttention)
        #expect(harness.model.canRetryRestore && !harness.model.canActivate)
        harness.stop()
    }

    @Test
    func theIconKeepsItsShapeWhileApplyingRestoringOrRollingBack() async {
        let harness = MenuBarTestHarness()
        await harness.start()

        await harness.session.emit(.active(MenuBarFixtures.activeSession))
        #expect(await harness.eventually { harness.model.iconShape == .active })
        await harness.session.emit(.restoring(sessionID: id, profileName: "Quick"))
        #expect(await harness.eventually { harness.model.presentation == .restoring(profileName: "Quick") })

        #expect(harness.model.iconShape == .active)
        harness.stop()
    }

    @Test
    func aSecondClickWhileActivatingDoesNotStartASecondActivation() async {
        let harness = MenuBarTestHarness()
        await harness.start()
        await harness.session.setActivation(.success(.performed(MenuBarFixtures.activeSession)))
        await harness.session.closeGate()

        async let first: Void = harness.model.activate(MenuBarFixtures.quick)
        #expect(await harness.eventually { harness.model.isTriggerRunning })
        await harness.model.activate(MenuBarFixtures.quick)
        await harness.session.openGate()
        await first

        #expect(await harness.session.calls == ["recover", "activate Quick"])
        harness.stop()
    }

    @Test
    func aFailedActivationNamesTheActionAndWhetherItWasUndone() async {
        let harness = MenuBarTestHarness()
        await harness.start()
        let failure = ActionFailure(identifier: .dock, reason: "-1743")
        await harness.session.setActivation(
            .failure(.applyFailed(failure, rollback: MenuBarFixtures.report(restored: [.dock]))))

        await harness.model.activate(MenuBarFixtures.full)

        #expect(harness.model.notice == .activationFailed(.dock, .undone))
        #expect(harness.model.notice?.mentionsAutomationPermission == true)
        #expect(!harness.model.isTriggerRunning)
        harness.stop()
    }

    @Test
    func anIgnoredTriggerIsNotAnError() async {
        let harness = MenuBarTestHarness()
        await harness.start()

        await harness.model.activate(MenuBarFixtures.quick)

        #expect(harness.model.notice == nil)
        harness.stop()
    }

    @Test
    func stoppingNamesTheActionsTheUserChanged() async {
        let harness = MenuBarTestHarness(state: .active(MenuBarFixtures.activeSession))
        await harness.start()
        #expect(await harness.eventually { harness.model.canStop })
        await harness.session.setDeactivation(
            .success(.performed(MenuBarFixtures.report(restored: [.dock], skipped: [.wallpaper]))))

        await harness.model.deactivate()

        #expect(harness.model.notice == .keptUserChanges([.wallpaper]))
        harness.stop()
    }

    @Test
    func aSessionFileThatCannotBeRemovedAfterStopIsReported() async {
        let harness = MenuBarTestHarness(state: .active(MenuBarFixtures.activeSession))
        await harness.start()
        #expect(await harness.eventually { harness.model.canStop })
        await harness.session.setDeactivation(
            .failure(.sessionStoreFailed(.ioFailure(fileName: "session.json", reason: "x"))))

        await harness.model.deactivate()

        #expect(harness.model.notice == .sessionFileNotRemoved)
        harness.stop()
    }

    @Test
    func stopAndRetryAreIgnoredWhenTheStateDoesNotAcceptThem() async {
        let harness = MenuBarTestHarness()
        await harness.start()

        await harness.model.deactivate()
        await harness.model.retryRestore()
        harness.model.requestDiscardUnreadableSession()

        #expect(await harness.session.calls == ["recover"])
        #expect(!harness.model.isConfirmingDiscard)
        harness.stop()
    }

    @Test
    func aSuccessfulRetryNamesTheActionsTheUserChanged() async {
        let harness = MenuBarTestHarness(state: restoreFailed)
        await harness.start()
        #expect(await harness.eventually { harness.model.canRetryRestore })
        await harness.session.setRetry(
            .performed(.restored(MenuBarFixtures.report(restored: [.dock], skipped: [.menuBar]))))

        await harness.model.retryRestore()

        #expect(await harness.session.calls == ["recover", "retry"])
        #expect(harness.model.notice == .keptUserChanges([.menuBar]))
        harness.stop()
    }

    @Test
    func discardingAnUnreadableSessionFileNeedsAConfirmationAndCanBeCancelled() async {
        let unreadable = SessionState.degraded(
            .unreadableSessionFile(.corrupted(fileName: "session.json", reason: "x")))
        let harness = MenuBarTestHarness(state: unreadable)
        await harness.start()
        #expect(await harness.eventually { harness.model.canDiscardSessionFile })

        await harness.model.confirmDiscard()
        harness.model.requestDiscardUnreadableSession()
        #expect(harness.model.isConfirmingDiscard)
        harness.model.cancelDiscard()
        #expect(!harness.model.isConfirmingDiscard)
        #expect(await harness.session.calls == ["recover"])

        harness.model.requestDiscardUnreadableSession()
        await harness.model.confirmDiscard()

        #expect(await harness.session.calls == ["recover", "discard"])
        #expect(!harness.model.isConfirmingDiscard)
        harness.stop()
    }

    @Test
    func aDiscardThatFailsIsReported() async {
        let harness = MenuBarTestHarness(state: unreadable)
        await harness.start()
        #expect(await harness.eventually { harness.model.canDiscardSessionFile })
        await harness.session.setDiscard(
            .failure(.sessionStoreFailed(.ioFailure(fileName: "session.json", reason: "x"))))

        harness.model.requestDiscardUnreadableSession()
        await harness.model.confirmDiscard()

        #expect(harness.model.notice == .discardFailed)
        harness.stop()
    }

    @Test
    func theConfirmationEndsWhenTheStateNoLongerAcceptsADiscard() async {
        let harness = MenuBarTestHarness(state: unreadable)
        await harness.start()
        #expect(await harness.eventually { harness.model.canDiscardSessionFile })
        harness.model.requestDiscardUnreadableSession()

        await harness.session.emit(.idle)

        #expect(await harness.eventually { !harness.model.isConfirmingDiscard })
        harness.stop()
    }
}
