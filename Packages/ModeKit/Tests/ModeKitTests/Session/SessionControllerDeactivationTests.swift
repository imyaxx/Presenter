import Foundation
import ModeKit
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SessionControllerDeactivationTests {
    private let harness = SessionControllerHarness()
    private typealias Fixture = SessionControllerHarness

    // Scenario 3
    @Test
    func deactivateRestoresInReverseRemovesSessionFileAndReturnsToIdle() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.desktopIcons, .dock, .menuBar]))

        let result = try await controller.deactivate()

        #expect(
            result
                == .performed(
                    RestoreReport(
                        restored: [.menuBar, .dock, .desktopIcons], skippedBecauseChangedByUser: [], failed: [], )))
        let restores = await harness.log.calls.filter { if case .restore = $0 { true } else { false } }
        #expect(restores.count == 3)
        #expect(
            restores.first
                == .restore(.menuBar, snapshot: Fixture.snapshot(.menuBar), applied: Fixture.applied(.menuBar)))
        #expect(try await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }

    // Scenario 4 (degraded part; the retry is in SessionControllerRetryTests)
    @Test
    func restoreFailureOnOneActionStillRestoresOthersKeepsItsRecordAndDegrades() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.desktopIcons, .dock, .menuBar]))
        try await harness.action(.dock).failRestore()

        let result = try await controller.deactivate()

        let failure = ActionFailure(identifier: .dock, reason: "restore dock")
        #expect(
            result
                == .performed(
                    RestoreReport(
                        restored: [.menuBar, .desktopIcons], skippedBecauseChangedByUser: [], failed: [failure], )))
        let file = try #require(try await harness.sessionFile())
        #expect(file.actions.map(\.identifier) == [.dock])
        #expect(file.actions.first?.appliedData != nil)
        guard case .degraded(.restoreFailed(_, "Screen share", [failure])) = await controller.state else {
            Issue.record("expected degraded")
            return
        }
    }

    // Scenario 5
    @Test
    func valueChangedByUserIsSkippedAndReported() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.dock, .menuBar]))
        try await harness.action(.dock).scriptRestores([.success(.skippedBecauseChangedByUser)])

        let result = try await controller.deactivate()

        #expect(
            result == .performed(RestoreReport(restored: [.menuBar], skippedBecauseChangedByUser: [.dock], failed: [])))
        #expect(try await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }

    // Scenario 10
    @Test
    func failedRewriteOfFailedRecordsLeavesPreviousSessionFileIntact() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.dock, .menuBar]))
        let before = await harness.fileStore.contents(of: Fixture.sessionFileURL)
        try await harness.action(.dock).failRestore()
        await harness.fileStore.failNextWrite()

        _ = try await controller.deactivate()

        #expect(await harness.fileStore.contents(of: Fixture.sessionFileURL) == before)
        guard case .degraded = await controller.state else {
            Issue.record("expected degraded")
            return
        }
    }

    @Test
    func failureToRemoveSessionFileAfterCompleteRestoreThrowsAndEndsIdle() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.dock]))
        await harness.fileStore.failNextRemove()

        await #expect {
            try await controller.deactivate()
        } throws: { error in
            guard case .sessionStoreFailed(.ioFailure("session.json", _)) = error as? SessionError else {
                return false
            }
            return true
        }
        #expect(await controller.state == .idle)
    }

    @Test
    func everyTransitionAndStepIsLoggedWithTheSessionID() async throws {
        let controller = await harness.ready()
        guard case .performed(let session) = try await controller.activate(Fixture.profile([.dock])) else {
            Issue.record("activate was ignored")
            return
        }
        _ = try await controller.deactivate()

        let id = session.sessionID
        let applying = SessionState.applying(sessionID: id, profileName: "Screen share")
        let restoring = SessionState.restoring(sessionID: id, profileName: "Screen share")
        #expect(
            harness.logger.events.suffix(7) == [
                .stateChanged(previous: .idle, current: applying, sessionID: id),
                .actionCaptured(sessionID: id, .dock),
                .actionApplied(sessionID: id, .dock),
                .stateChanged(previous: applying, current: .active(session), sessionID: id),
                .stateChanged(previous: .active(session), current: restoring, sessionID: id),
                .actionRestored(sessionID: id, .dock),
                .stateChanged(previous: restoring, current: .idle, sessionID: id),
            ]
        )
    }
}
