import Foundation
import ModeKit
import Testing

// Scenario 7
@Suite(.timeLimit(.minutes(1)))
struct SessionControllerReentrancyTests {
    private let harness = SessionControllerHarness()
    private typealias Fixture = SessionControllerHarness

    @Test
    func twoActivationsRacingAcrossAnAwaitProduceOneTransitionAndOneIgnored() async throws {
        let controller = await harness.ready()
        let gate = AsyncGate()
        try await harness.action(.dock).suspend(in: .capture, at: gate)
        let profile = Fixture.profile([.dock])

        async let first = controller.activate(profile)
        async let second = controller.activate(profile)
        await gate.waitForArrival()
        await gate.open()
        let results = [try await first, try await second]

        #expect(results.filter { if case .performed = $0 { true } else { false } }.count == 1)
        #expect(results.filter { if case .ignored(.applying) = $0 { true } else { false } }.count == 1)
        let toApplying = harness.logger.events.filter {
            if case .stateChanged(.idle, .applying, _) = $0 { true } else { false }
        }
        #expect(toApplying.count == 1)
        #expect(await harness.log.calls.filter { $0 == .capture(.dock) }.count == 1)
    }

    @Test
    func triggersDuringApplyingAreIgnoredAndNotQueued() async throws {
        let controller = await harness.ready()
        let gate = AsyncGate()
        try await harness.action(.dock).suspend(in: .apply, at: gate)
        let activation = Task { try await controller.activate(Fixture.profile([.dock])) }
        await gate.waitForArrival()
        let applying = await controller.state

        #expect(try await controller.activate(Fixture.profile([.menuBar])) == .ignored(currentState: applying))
        #expect(try await controller.deactivate() == .ignored(currentState: applying))
        await gate.open()
        _ = try await activation.value

        guard case .active = await controller.state else {
            Issue.record("expected active")
            return
        }
        #expect(await !harness.log.calls.contains(.capture(.menuBar)))
    }

    @Test
    func triggersDuringRestoringAreIgnored() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(Fixture.profile([.dock]))
        let gate = AsyncGate()
        try await harness.action(.dock).suspend(in: .restore, at: gate)
        let deactivation = Task { try await controller.deactivate() }
        await gate.waitForArrival()
        let restoring = await controller.state

        #expect(try await controller.deactivate() == .ignored(currentState: restoring))
        #expect(try await controller.activate(Fixture.profile([.dock])) == .ignored(currentState: restoring))
        await gate.open()
        _ = try await deactivation.value

        #expect(await controller.state == .idle)
    }

    @Test
    func triggersDuringRollingBackAreIgnored() async throws {
        let controller = await harness.ready()
        try await harness.action(.menuBar).failApply()
        let gate = AsyncGate()
        try await harness.action(.dock).suspend(in: .restore, at: gate)
        let activation = Task { try await controller.activate(Fixture.profile([.dock, .menuBar])) }
        await gate.waitForArrival()
        let rollingBack = await controller.state

        guard case .rollingBack = rollingBack else {
            Issue.record("expected rollingBack, got \(rollingBack)")
            return
        }
        #expect(try await controller.activate(Fixture.profile([.dock])) == .ignored(currentState: rollingBack))
        #expect(try await controller.deactivate() == .ignored(currentState: rollingBack))
        await gate.open()
        await #expect(throws: SessionError.self) { try await activation.value }
        #expect(await controller.state == .idle)
    }
}
