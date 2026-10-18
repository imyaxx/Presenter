import Foundation
import ModeKit
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SessionControllerDegradedTests {
    private let harness = SessionControllerHarness()
    private typealias Fixture = SessionControllerHarness

    private func degradeByFailingDockRestore(
        then laterResults: [Result<RestoreOutcome, FakeActionFailure>]
    ) async throws -> SessionController {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.dock, .menuBar]))
        try await harness.action(.dock).scriptRestores([.failure(FakeActionFailure(message: "busy"))] + laterResults)
        _ = try await controller.deactivate()
        return controller
    }

    // Scenario 4 (retry)
    @Test
    func retryAfterRestoreFailureSucceedsLaterAndEndsIdle() async throws {
        let controller = try await degradeByFailingDockRestore(then: [.success(.restored)])

        let retry = await controller.retryRestore()

        #expect(
            retry
                == .performed(.restored(RestoreReport(restored: [.dock], skippedBecauseChangedByUser: [], failed: []))))
        #expect(
            await harness.log.calls.last
                == .restore(.dock, snapshot: Fixture.snapshot(.dock), applied: Fixture.applied(.dock)))
        #expect(try await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }

    @Test
    func retryThatStillFailsStaysDegradedWithTheRecordKept() async throws {
        let controller = try await degradeByFailingDockRestore(then: [
            .failure(FakeActionFailure(message: "still busy"))
        ])

        let retry = await controller.retryRestore()

        guard case .performed(.partiallyRestored(let report)) = retry else {
            Issue.record("expected partiallyRestored, got \(retry)")
            return
        }
        #expect(report.failed == [ActionFailure(identifier: .dock, reason: "still busy")])
        #expect(try await harness.sessionFile()?.actions.map(\.identifier) == [.dock])
        guard case .degraded(.restoreFailed) = await controller.state else {
            Issue.record("expected degraded")
            return
        }
    }

    @Test
    func retryRestoresAnUnreadableFileOnceItBecameReadable() async throws {
        await harness.fileStore.place(Data("{".utf8), at: Fixture.sessionFileURL)
        _ = await harness.controller.recoverIfNeeded()
        let record = ActionRecord(
            identifier: .dock,
            snapshotData: try JSONEncoder().encode(Fixture.snapshot(.dock)),
            appliedData: nil,
        )
        try await harness.fileStore.remove(Fixture.sessionFileURL)
        try await harness.writeSessionFile(SessionRecordBuilder(actions: [record]).build())

        let retry = await harness.controller.retryRestore()

        #expect(
            retry
                == .performed(.restored(RestoreReport(restored: [.dock], skippedBecauseChangedByUser: [], failed: []))))
        #expect(await harness.controller.state == .idle)
    }

    @Test
    func retryAndDiscardOutsideTheirStatesAreIgnored() async throws {
        let controller = await harness.ready()

        #expect(await controller.retryRestore() == .ignored(currentState: .idle))
        let discard = try await controller.discardUnreadableSession()
        guard case .ignored(.idle) = discard else {
            Issue.record("expected ignored")
            return
        }
    }

    @Test
    func discardIsIgnoredWhenDegradedByARestoreFailure() async throws {
        let controller = try await degradeByFailingDockRestore(then: [])
        let state = await controller.state

        let discard = try await controller.discardUnreadableSession()

        guard case .ignored(let currentState) = discard else {
            Issue.record("expected ignored")
            return
        }
        #expect(currentState == state)
        #expect(try await harness.sessionFile() != nil)
    }

    @Test
    func discardRemovesTheUnreadableFileAndAllowsActivation() async throws {
        await harness.fileStore.place(Data(#"{"schemaVersion":9}"#.utf8), at: Fixture.sessionFileURL)
        _ = await harness.controller.recoverIfNeeded()

        let discard = try await harness.controller.discardUnreadableSession()

        guard case .performed = discard else {
            Issue.record("expected performed")
            return
        }
        #expect(await harness.fileStore.contents(of: Fixture.sessionFileURL) == nil)
        #expect(await harness.controller.state == .idle)
        guard case .performed = try await harness.controller.activate(Fixture.profile([.dock])) else {
            Issue.record("expected activation to be performed")
            return
        }
    }

    @Test
    func discardThatCannotRemoveTheFileThrowsAndStaysDegraded() async {
        await harness.fileStore.place(Data("{".utf8), at: Fixture.sessionFileURL)
        _ = await harness.controller.recoverIfNeeded()
        let degraded = await harness.controller.state
        await harness.fileStore.failNextRemove()

        await #expect(throws: SessionError.self) {
            try await harness.controller.discardUnreadableSession()
        }
        #expect(await harness.controller.state == degraded)
    }

    @Test
    func twoRetriesRacingAcrossAnAwaitProduceOneRetryAndOneIgnored() async throws {
        let controller = try await degradeByFailingDockRestore(then: [.success(.restored)])

        async let first = controller.retryRestore()
        async let second = controller.retryRestore()
        let results = [await first, await second]

        #expect(results.filter { if case .performed = $0 { true } else { false } }.count == 1)
        #expect(results.filter { if case .ignored(.degraded) = $0 { true } else { false } }.count == 1)
        #expect(await controller.state == .idle)
    }
}
