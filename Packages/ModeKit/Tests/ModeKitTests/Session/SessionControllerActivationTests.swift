import Foundation
import ModeKit
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SessionControllerActivationTests {
    private let harness = SessionControllerHarness()
    private static let fiveSteps: [ActionIdentifier] = [.desktopIcons, .dock, .menuBar, .hideApps, .wallpaper]

    // Scenario 1
    @Test
    func activateCapturesAllWritesSessionBeforeFirstApplyAndAppliesInProfileOrder() async throws {
        let controller = await harness.ready()
        let fileAtFirstApply = ValueBox<SessionRecord>()
        let harness = harness
        try await harness.action(.desktopIcons).onApply {
            // A read failure leaves the box empty, which the #require below reports.
            await fileAtFirstApply.set(try? await harness.sessionFile())
        }

        let result = try await controller.activate(SessionControllerHarness.profile(Self.fiveSteps))

        guard case .performed(let session) = result else {
            Issue.record("activate was ignored")
            return
        }
        let firstApplyFile = try #require(await fileAtFirstApply.value)
        #expect(firstApplyFile.actions.map(\.identifier) == Self.fiveSteps)
        #expect(firstApplyFile.actions.allSatisfy { $0.appliedData == nil })
        #expect(await harness.log.calls == Self.fiveSteps.map(FakeCall.capture) + Self.fiveSteps.map(FakeCall.apply))
        let finalFile = try #require(try await harness.sessionFile())
        #expect(finalFile.actions.allSatisfy { $0.appliedData != nil })
        #expect(finalFile.sessionID == session.sessionID)
        #expect(await controller.state == .active(session))
    }

    @Test
    func subscriberStartedBeforeActivateSeesEveryState() async throws {
        let controller = await harness.ready()
        let updates = await controller.stateUpdates()

        let result = try await controller.activate(SessionControllerHarness.profile([.dock]))

        guard case .performed(let session) = result else {
            Issue.record("activate was ignored")
            return
        }
        let states = await take(3, from: updates)
        #expect(
            states == [.idle, .applying(sessionID: session.sessionID, profileName: "Screen share"), .active(session)])
    }

    @Test
    func subscriberThatStoppedIsDroppedWhileOthersKeepReceiving() async throws {
        let controller = await harness.ready()
        var stopped: AsyncStream<SessionState>? = await controller.stateUpdates()
        if let stream = stopped {
            _ = await take(1, from: stream)
        }
        stopped = nil
        let listening = await controller.stateUpdates()

        _ = try await controller.activate(SessionControllerHarness.profile([.dock]))
        _ = try await controller.deactivate()

        let states = await take(5, from: listening)
        #expect(states.first == .idle)
        #expect(states.last == .idle)
    }

    // Scenario 9
    @Test
    func emptyProfileActivatesWithZeroRecordsAndDeactivates() async throws {
        let controller = await harness.ready()

        let result = try await controller.activate(SessionControllerHarness.profile([]))

        guard case .performed = result else {
            Issue.record("activate was ignored")
            return
        }
        #expect(try await harness.sessionFile()?.actions == [])
        #expect(
            try await controller.deactivate()
                == .performed(RestoreReport(restored: [], skippedBecauseChangedByUser: [], failed: [])))
        #expect(await controller.state == .idle)
        #expect(try await harness.sessionFile() == nil)
    }

    @Test(arguments: [[ActionIdentifier.menuBar], fiveSteps])
    func singleStepAndAllStepsActivateAndRestoreInReverse(identifiers: [ActionIdentifier]) async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(SessionControllerHarness.profile(identifiers))

        let report = try await controller.deactivate()

        #expect(
            report
                == .performed(
                    RestoreReport(restored: identifiers.reversed(), skippedBecauseChangedByUser: [], failed: [])))
    }

    @Test
    func duplicateStepsAreRejectedBeforeAnythingIsTouched() async {
        let controller = await harness.ready()
        let profile = ProfileBuilder(steps: [.hideDock, .hideDock]).build()

        await #expect(throws: SessionError.invalidProfile(.duplicateStep(.dock))) {
            try await controller.activate(profile)
        }

        #expect(await harness.log.calls.isEmpty)
        #expect(await harness.fileStore.files.isEmpty)
        #expect(await controller.state == .idle)
    }

    @Test
    func activateBeforeRecoveryThrowsRecoveryNotRun() async {
        await #expect(throws: SessionError.recoveryNotRun) {
            try await harness.controller.activate(SessionControllerHarness.profile([.dock]))
        }
        #expect(await harness.log.calls.isEmpty)
    }

    @Test(arguments: [ActionIdentifier.desktopIcons, .menuBar, .wallpaper])
    func captureFailureAppliesNothingWritesNothingAndReturnsToIdle(failing: ActionIdentifier) async throws {
        let controller = await harness.ready()
        try await harness.action(failing).failCapture()

        await #expect(
            throws: SessionError.captureFailed(
                ActionFailure(identifier: failing, reason: "capture \(failing.rawValue)"))
        ) {
            try await controller.activate(SessionControllerHarness.profile(Self.fiveSteps))
        }

        #expect(await !harness.log.calls.contains { if case .apply = $0 { true } else { false } })
        #expect(try await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }

    @Test
    func unregisteredActionFailsAsCaptureFailureBeforeAnythingIsTouched() async {
        let harness = SessionControllerHarness(registered: [.dock])
        let controller = await harness.ready()

        await #expect {
            try await controller.activate(SessionControllerHarness.profile([.dock, .wallpaper]))
        } throws: { error in
            guard case .captureFailed(let failure) = error as? SessionError else {
                return false
            }
            return failure.identifier == .wallpaper
        }
        #expect(await harness.log.calls.isEmpty)
        #expect(await controller.state == .idle)
    }

    @Test
    func sessionWriteFailureBeforeFirstApplyAppliesNothing() async {
        let controller = await harness.ready()
        await harness.fileStore.failNextWrite()

        await #expect {
            try await controller.activate(SessionControllerHarness.profile(Self.fiveSteps))
        } throws: { error in
            guard case .sessionStoreFailed(.ioFailure("session.json", _)) = error as? SessionError else {
                return false
            }
            return true
        }

        #expect(await harness.log.calls == Self.fiveSteps.map(FakeCall.capture))
        #expect(await controller.state == .idle)
    }

    @Test
    func activateWhileActiveIsIgnoredAndLogged() async throws {
        let controller = await harness.ready()
        _ = try await controller.activate(SessionControllerHarness.profile([.dock]))
        let state = await controller.state

        let second = try await controller.activate(SessionControllerHarness.profile([.menuBar]))

        #expect(second == .ignored(currentState: state))
        #expect(harness.logger.events.contains(.triggerIgnored(.activate, state: state)))
    }

    @Test
    func deactivateFromIdleIsIgnored() async throws {
        let controller = await harness.ready()

        #expect(try await controller.deactivate() == .ignored(currentState: .idle))
        #expect(harness.logger.events.contains(.triggerIgnored(.deactivate, state: .idle)))
    }
}
