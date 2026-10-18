import Foundation
import ModeKit
import Testing

// Scenario 6
@Suite(.timeLimit(.minutes(1)))
struct SessionControllerRecoveryTests {
    private let harness = SessionControllerHarness()
    private typealias Fixture = SessionControllerHarness

    private static func record(_ identifier: ActionIdentifier, applied: Bool) throws -> ActionRecord {
        ActionRecord(
            identifier: identifier,
            snapshotData: try JSONEncoder().encode(Fixture.snapshot(identifier)),
            appliedData: applied ? try JSONEncoder().encode(Fixture.applied(identifier)) : nil,
        )
    }

    private static func leftoverSession(_ actions: [ActionRecord]) -> SessionRecord {
        // The profile ID belongs to no stored profile: recovery must not need it.
        SessionRecordBuilder(profileID: UUID(), profileName: "Deleted profile", actions: actions).build()
    }

    @Test
    func noSessionFileMeansNothingToRecoverAndLaterCallsAreAlreadyAttempted() async {
        #expect(await harness.controller.recoverIfNeeded() == .nothingToRecover)
        #expect(await harness.controller.recoverIfNeeded() == .alreadyAttempted)
        #expect(await harness.controller.state == .idle)
    }

    @Test
    func leftoverSessionIsRestoredInReverseWithoutTheProfileBeforeAnyActivation() async throws {
        try await harness.writeSessionFile(
            Self.leftoverSession([try Self.record(.dock, applied: true), try Self.record(.menuBar, applied: true)])
        )

        let outcome = await harness.controller.recoverIfNeeded()

        #expect(
            outcome
                == .restored(RestoreReport(restored: [.menuBar, .dock], skippedBecauseChangedByUser: [], failed: [])))
        #expect(
            await harness.log.calls == [
                .restore(.menuBar, snapshot: Fixture.snapshot(.menuBar), applied: Fixture.applied(.menuBar)),
                .restore(.dock, snapshot: Fixture.snapshot(.dock), applied: Fixture.applied(.dock)),
            ]
        )
        #expect(try await harness.sessionFile() == nil)
        #expect(await harness.controller.state == .idle)
        #expect(harness.clock.sleeperCount == 0)
        #expect(try await harness.controller.activate(Fixture.profile([.dock])) != .ignored(currentState: .idle))
    }

    @Test
    func interruptedApplyIsRestoredUnconditionally() async throws {
        try await harness.writeSessionFile(
            Self.leftoverSession([try Self.record(.dock, applied: true), try Self.record(.wallpaper, applied: false)])
        )

        _ = await harness.controller.recoverIfNeeded()

        #expect(
            await harness.log.calls.first == .restore(.wallpaper, snapshot: Fixture.snapshot(.wallpaper), applied: nil))
    }

    @Test(arguments: [
        #"{"schemaVersion":1,"session":"#,
        #"{"schemaVersion":4,"session":{"from":"the future"}}"#,
    ])
    func unreadableSessionFileBlocksRecoveryDegradesAndIsNotTouched(contents: String) async {
        let original = Data(contents.utf8)
        await harness.fileStore.place(original, at: Fixture.sessionFileURL)

        let outcome = await harness.controller.recoverIfNeeded()

        guard case .blocked(let error) = outcome else {
            Issue.record("expected blocked, got \(outcome)")
            return
        }
        #expect(await harness.controller.state == .degraded(.unreadableSessionFile(error)))
        #expect(await harness.fileStore.contents(of: Fixture.sessionFileURL) == original)
        #expect(await harness.log.calls.isEmpty)
        let activation = try? await harness.controller.activate(Fixture.profile([.dock]))
        #expect(activation == .ignored(currentState: .degraded(.unreadableSessionFile(error))))
    }

    @Test
    func undecodableSnapshotIsAFailureKeptInTheFileWhileOthersRestore() async throws {
        let broken = ActionRecord(identifier: .dock, snapshotData: Data("garbage".utf8), appliedData: nil)
        try await harness.writeSessionFile(Self.leftoverSession([broken, try Self.record(.menuBar, applied: true)]))

        let outcome = await harness.controller.recoverIfNeeded()

        guard case .partiallyRestored(let report) = outcome else {
            Issue.record("expected partiallyRestored, got \(outcome)")
            return
        }
        #expect(report.restored == [.menuBar])
        #expect(report.failed.map(\.identifier) == [.dock])
        #expect(try await harness.sessionFile()?.actions == [broken])
        guard case .degraded(.restoreFailed) = await harness.controller.state else {
            Issue.record("expected degraded")
            return
        }
    }

    @Test
    func actionWithoutRegisteredRestorerIsAFailureKeptInTheFile() async throws {
        let harness = SessionControllerHarness(registered: [.dock])
        let orphan = try Self.record(.wallpaper, applied: true)
        try await harness.writeSessionFile(Self.leftoverSession([try Self.record(.dock, applied: true), orphan]))

        let outcome = await harness.controller.recoverIfNeeded()

        let failure = ActionFailure(identifier: .wallpaper, error: ActionError.unsupported(.wallpaper))
        #expect(
            outcome
                == .partiallyRestored(
                    RestoreReport(restored: [.dock], skippedBecauseChangedByUser: [], failed: [failure])))
        #expect(try await harness.sessionFile()?.actions == [orphan])
    }
}

extension ActionFailure {
    init(identifier: ActionIdentifier, error: any Error) {
        self.init(identifier: identifier, reason: String(describing: error))
    }
}
