import Foundation
import ModeKit
import Testing

@testable import PresenterApp

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct QuitCoordinatorTests {
    private let active = SessionState.active(MenuBarFixtures.activeSession)

    @Test
    func quittingWhileIdleRestoresNothing() async {
        let session = FakeSessionController(state: .idle)

        let outcome = await QuitCoordinator(session: session, clock: StoppedClock()).prepareToQuit()

        #expect(outcome == .nothingToRestore)
        #expect(await session.calls.isEmpty)
    }

    @Test
    func quittingWhileDegradedLeavesTheSessionFileForTheNextLaunch() async {
        let failure = ActionFailure(identifier: .dock, reason: "x")
        let session = FakeSessionController(
            state: .degraded(.restoreFailed(sessionID: UUID(), profileName: "Q", failures: [failure])))

        let outcome = await QuitCoordinator(session: session, clock: StoppedClock()).prepareToQuit()

        #expect(outcome == .nothingToRestore)
        #expect(await session.calls.isEmpty)
    }

    @Test
    func quittingWhileActiveRestoresFirst() async {
        let session = FakeSessionController(state: active)
        await session.setDeactivation(.success(.performed(MenuBarFixtures.report(restored: [.desktopIcons]))))

        let outcome = await QuitCoordinator(session: session, clock: StoppedClock()).prepareToQuit()

        #expect(outcome == .restored)
        #expect(await session.calls == ["deactivate"])
    }

    @Test
    func aRestoreThatLeavesFailuresStillLetsTheAppQuit() async {
        let session = FakeSessionController(state: active)
        await session.setDeactivation(.success(.performed(MenuBarFixtures.report(failed: [.dock]))))

        #expect(
            await QuitCoordinator(session: session, clock: StoppedClock()).prepareToQuit() == .restoredWithFailures)
    }

    @Test
    func aSessionFileErrorDuringTheRestoreStillLetsTheAppQuit() async {
        let session = FakeSessionController(state: active)
        await session.setDeactivation(.failure(.sessionStoreFailed(.ioFailure(fileName: "session.json", reason: "x"))))

        #expect(
            await QuitCoordinator(session: session, clock: StoppedClock()).prepareToQuit() == .restoredWithFailures)
    }

    @Test
    func aRestorePastTheDeadlineLetsTheAppQuitAndKeepsRunning() async {
        let session = FakeSessionController(state: active)
        await session.setDeactivation(.success(.performed(MenuBarFixtures.report(restored: [.dock]))))
        await session.closeGate()

        let outcome = await QuitCoordinator(session: session, clock: ImmediateClock()).prepareToQuit()

        #expect(outcome == .deadlineReached)
        #expect(await session.calls == ["deactivate"])
        await session.openGate()
    }

    @Test
    func theDeadlineIsFifteenSeconds() {
        #expect(QuitCoordinator.restoreDeadline == .seconds(15))
    }
}
