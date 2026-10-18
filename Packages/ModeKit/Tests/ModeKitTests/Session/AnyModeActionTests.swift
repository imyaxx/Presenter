import Foundation
import Testing

@testable import ModeKit

struct AnyModeActionTests {
    private let log = FakeCallLog()

    @Test
    func captureAndApplyEncodeAndRestoreDecodesThem() async throws {
        let fake = FakeModeAction(.dock, log: log)
        let action = AnyModeAction(fake)

        let snapshotData = try await action.capture()
        let appliedData = try await action.apply()
        let record = ActionRecord(identifier: .dock, snapshotData: snapshotData, appliedData: appliedData)
        let outcome = try await action.restorer.restore(record)

        #expect(outcome == .restored)
        let snapshot = FakeSnapshot(value: "dock-snapshot")
        let applied = FakeAppliedState(value: "dock-applied")
        #expect(await log.calls.last == .restore(.dock, snapshot: snapshot, applied: applied))
    }

    @Test
    func missingAppliedDataRestoresUnconditionally() async throws {
        let fake = FakeModeAction(.menuBar, log: log)
        let action = AnyModeAction(fake)

        let record = ActionRecord(identifier: .menuBar, snapshotData: try await action.capture(), appliedData: nil)
        _ = try await AnyActionRestorer(fake).restore(record)

        #expect(
            await log.calls.last == .restore(.menuBar, snapshot: FakeSnapshot(value: "menuBar-snapshot"), applied: nil))
    }

    @Test(arguments: [
        ActionRecord(identifier: .dock, snapshotData: Data("not json".utf8), appliedData: nil),
        ActionRecord(identifier: .dock, snapshotData: Data(#"{"value":"ok"}"#.utf8), appliedData: Data("[]".utf8)),
    ])
    func undecodableRecordFailsWithoutCallingTheAction(record: ActionRecord) async {
        let restorer = AnyActionRestorer(FakeModeAction(.dock, log: log))

        await #expect {
            try await restorer.restore(record)
        } throws: { error in
            guard case .undecodableRecord(.dock, _) = error as? ActionError else {
                return false
            }
            return true
        }
        #expect(await log.calls.isEmpty)
    }

    @Test
    func actionErrorsPropagate() async {
        let fake = FakeModeAction(.wallpaper, log: log)
        await fake.failCapture()
        await fake.failApply()
        let action = AnyModeAction(fake)

        await #expect(throws: FakeActionFailure(message: "capture wallpaper")) { try await action.capture() }
        await #expect(throws: FakeActionFailure(message: "apply wallpaper")) { try await action.apply() }
    }
}
