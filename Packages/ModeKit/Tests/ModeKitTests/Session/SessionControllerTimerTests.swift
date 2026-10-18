import Foundation
import ModeKit
import Testing

// Scenario 8
@Suite(.timeLimit(.minutes(1)))
struct SessionControllerTimerTests {
    private let harness = SessionControllerHarness()
    private typealias Fixture = SessionControllerHarness

    @Test
    func autoExitFiresAfterTheProfileDurationAndRestores() async throws {
        let controller = await harness.ready()
        let profile = Fixture.profile([.dock], autoExit: try AutoExit(seconds: 60))
        let updates = await controller.stateUpdates()
        _ = try await controller.activate(profile)
        await harness.clock.waitForSleeper()

        harness.clock.advance(by: .seconds(59))
        #expect(harness.clock.sleeperCount == 1)
        harness.clock.advance(by: .seconds(1))

        let states = await take(5, from: updates)
        #expect(states.last == .idle)
        #expect(
            await harness.log.calls.last
                == .restore(.dock, snapshot: Fixture.snapshot(.dock), applied: Fixture.applied(.dock)))
        #expect(try await harness.sessionFile() == nil)
    }

    @Test
    func manualDeactivateCancelsTheTimer() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.dock], autoExit: try AutoExit(seconds: 60)))
        await harness.clock.waitForSleeper()

        _ = try await controller.deactivate()
        harness.clock.advance(by: .seconds(120))

        #expect(harness.clock.sleeperCount == 0)
        let restoreCount = await harness.log.calls.filter { if case .restore = $0 { true } else { false } }.count
        #expect(restoreCount == 1)
        #expect(await controller.state == .idle)
    }

    @Test
    func profileWithoutAutoExitStartsNoTimer() async throws {
        let controller = await harness.ready()

        _ = try await controller.activate(Fixture.profile([.dock]))

        #expect(harness.clock.sleeperCount == 0)
    }

    @Test
    func staleTimerFiringDuringUserDeactivateDoesNothing() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.dock], autoExit: try AutoExit(seconds: 60)))
        await harness.clock.waitForSleeper()
        let gate = AsyncGate()
        try await harness.action(.dock).suspend(in: .restore, at: gate)
        let deactivation = Task { try await controller.deactivate() }
        await gate.waitForArrival()

        harness.clock.advance(by: .seconds(60))
        await gate.open()
        _ = try await deactivation.value

        let restoreCount = await harness.log.calls.filter { if case .restore = $0 { true } else { false } }.count
        #expect(restoreCount == 1)
        #expect(await controller.state == .idle)
    }
}
