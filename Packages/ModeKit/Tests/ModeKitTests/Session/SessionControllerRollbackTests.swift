import Foundation
import ModeKit
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SessionControllerRollbackTests {
    private let harness = SessionControllerHarness()
    private static let steps: [ActionIdentifier] = [.desktopIcons, .dock, .menuBar, .hideApps, .wallpaper]
    private typealias Fixture = SessionControllerHarness

    // Scenario 2
    @Test(arguments: [0, 2, 4])
    func applyFailureAtStepNRestoresItUnconditionallyAndEarlierStepsInReverse(failingIndex: Int) async throws {
        let controller = await harness.ready()
        let failing = Self.steps[failingIndex]
        try await harness.action(failing).failApply()

        await #expect {
            try await controller.activate(Fixture.profile(Self.steps))
        } throws: { error in
            let rolledBack = Array(Self.steps[...failingIndex].reversed())
            let rollback = RestoreReport(restored: rolledBack, skippedBecauseChangedByUser: [], failed: [])
            let failure = ActionFailure(identifier: failing, reason: "apply \(failing.rawValue)")
            return error as? SessionError == .applyFailed(failure, rollback: rollback)
        }

        let restores = await harness.log.calls.filter { if case .restore = $0 { true } else { false } }
        let expected = Self.steps[...failingIndex].reversed().map { identifier in
            FakeCall.restore(
                identifier,
                snapshot: Fixture.snapshot(identifier),
                applied: identifier == failing ? nil : Fixture.applied(identifier),
            )
        }
        #expect(restores == expected)
        #expect(try await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }

    @Test
    func recordPersistenceFailureAfterApplyRollsBackWithInMemoryAppliedState() async throws {
        let controller = await harness.ready()
        let fileStore = harness.fileStore
        try await harness.action(.dock).onApply { await fileStore.failNextWrite() }

        await #expect(throws: SessionError.self) {
            try await controller.activate(Fixture.profile([.desktopIcons, .dock, .menuBar]))
        }

        let restores = await harness.log.calls.filter { if case .restore = $0 { true } else { false } }
        let dockRestore = FakeCall.restore(.dock, snapshot: Fixture.snapshot(.dock), applied: Fixture.applied(.dock))
        let iconsRestore = FakeCall.restore(
            .desktopIcons,
            snapshot: Fixture.snapshot(.desktopIcons),
            applied: Fixture.applied(.desktopIcons),
        )
        #expect(restores == [dockRestore, iconsRestore])
        #expect(await !harness.log.calls.contains(.apply(.menuBar)))
        #expect(await controller.state == .idle)
    }

    @Test
    func failedRollbackRestoreKeepsOnlyThatRecordAndDegrades() async throws {
        let controller = await harness.ready()
        try await harness.action(.desktopIcons).failRestore()
        try await harness.action(.menuBar).failApply()
        let updates = await controller.stateUpdates()

        await #expect {
            try await controller.activate(Fixture.profile([.desktopIcons, .dock, .menuBar]))
        } throws: { error in
            guard case .applyFailed(_, let rollback) = error as? SessionError else {
                return false
            }
            return rollback.restored == [.menuBar, .dock] && rollback.failed.map(\.identifier) == [.desktopIcons]
        }

        let file = try #require(try await harness.sessionFile())
        #expect(file.actions.map(\.identifier) == [.desktopIcons])
        guard case .degraded(.restoreFailed(_, _, let failures)) = await controller.state else {
            Issue.record("expected degraded")
            return
        }
        #expect(failures.map(\.identifier) == [.desktopIcons])
        let states = await take(4, from: updates)
        guard case .rollingBack = states[2], case .degraded = states[3] else {
            Issue.record("expected rollingBack then degraded, got \(states)")
            return
        }
    }

    @Test
    func failureToRemoveSessionFileDuringRollbackDoesNotReplaceApplyError() async throws {
        let controller = await harness.ready()
        try await harness.action(.dock).failApply()
        await harness.fileStore.failNextRemove()

        await #expect {
            try await controller.activate(Fixture.profile([.dock]))
        } throws: { error in
            guard case .applyFailed = error as? SessionError else {
                return false
            }
            return true
        }

        #expect(await controller.state == .idle)
        #expect(
            harness.logger.events.contains { if case .sessionFileFailed(_, .remove, _) = $0 { true } else { false } })
    }
}
