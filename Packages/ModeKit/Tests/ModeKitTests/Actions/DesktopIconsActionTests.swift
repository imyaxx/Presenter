import Foundation
import ModeKit
import Testing

struct DesktopIconsActionTests {
    private static let key = DefaultsKey(domain: "com.apple.finder", name: "CreateDesktop")
    private static let killallFinder = ProcessCommand(
        executableURL: URL(filePath: "/usr/bin/killall"),
        arguments: ["Finder"],
        timeout: .seconds(10),
    )
    private typealias Snapshot = DesktopIconsAction.Snapshot
    private typealias Applied = DesktopIconsAction.AppliedState
    private static let hiddenApplied = Applied(createDesktop: .bool(false))

    private let processRunner = FakeProcessRunner()

    private func makeAction(_ initial: DefaultsValue?) -> (DesktopIconsAction, FakeDefaultsStore) {
        let defaults = FakeDefaultsStore(initial.map { [Self.key: $0] } ?? [:])
        return (DesktopIconsAction(defaults: defaults, processRunner: processRunner), defaults)
    }

    // Per-action scenario: capture reads current state
    @Test(arguments: [nil, DefaultsValue.bool(false), .bool(true), .integer(1)])
    func captureReadsTheKeyAndChangesNothing(initial: DefaultsValue?) async throws {
        let (action, defaults) = makeAction(initial)

        #expect(try await action.capture() == Snapshot(createDesktop: initial))
        #expect(await defaults.calls == [.read(Self.key)])
        #expect(await processRunner.commands.isEmpty)
    }

    // Per-action scenario: apply sets the expected state
    @Test(arguments: [nil, DefaultsValue.bool(true), .integer(1)])
    func applyWritesFalseAndRestartsFinder(initial: DefaultsValue?) async throws {
        let (action, defaults) = makeAction(initial)

        #expect(try await action.apply() == Applied(createDesktop: .bool(false)))
        #expect(await defaults.values[Self.key] == .bool(false))
        #expect(await processRunner.commands == [Self.killallFinder])
    }

    // Per-action scenario: state already equal to the target
    @Test
    func applyWhenIconsAreAlreadyHiddenDoesNothing() async throws {
        let (action, defaults) = makeAction(.bool(false))

        #expect(try await action.apply() == Applied(createDesktop: .bool(false)))
        #expect(await defaults.calls == [.read(Self.key)])
        #expect(await processRunner.commands.isEmpty)
    }

    @Test
    func finderNotRunningExitOneIsSuccess() async throws {
        let (action, _) = makeAction(nil)
        await processRunner.script(Self.killallFinder, .success(ProcessResult(exitCode: 1)))

        #expect(try await action.apply() == Applied(createDesktop: .bool(false)))
    }

    // Per-action scenario: the system call fails, and timeout
    @Test(arguments: [
        (Result<ProcessResult, any Error>.success(ProcessResult(exitCode: 2)), "killall Finder exited with 2"),
        (.failure(ProcessError.timedOut(.seconds(10))), ProcessError.timedOut(.seconds(10)).description),
        (.failure(ProcessError.launchFailed(reason: "no such file")), "Process could not be launched: no such file"),
    ])
    func killallFailureFailsTheApply(result: Result<ProcessResult, any Error>, diagnostic: String) async {
        let (action, _) = makeAction(nil)
        await processRunner.script(Self.killallFinder, result)

        await #expect {
            try await action.apply()
        } throws: { error in
            String(describing: error) == diagnostic
        }
    }

    @Test
    func writeFailureFailsTheApplyWithoutRestartingFinder() async {
        let (action, defaults) = makeAction(nil)
        await defaults.failNext(.write, with: DefaultsError.failed(reason: "read-only"))

        await #expect(throws: DefaultsError.failed(reason: "read-only")) { try await action.apply() }
        #expect(await processRunner.commands.isEmpty)
    }

    // Per-action scenario: restore returns to the captured state
    @Test(arguments: [DefaultsValue.bool(true), .integer(1)])
    func restoreWritesTheCapturedValueWithItsTypeAndRestartsFinder(captured: DefaultsValue) async throws {
        let (action, defaults) = makeAction(.bool(false))

        let outcome = try await action.restore(Snapshot(createDesktop: captured), expecting: Self.hiddenApplied)

        #expect(outcome == .restored)
        #expect(await defaults.values[Self.key] == captured)
        #expect(await processRunner.commands == [Self.killallFinder])
    }

    @Test
    func keyAbsentAtCaptureIsRemovedNeverWritten() async throws {
        let (action, defaults) = makeAction(.bool(false))

        _ = try await action.restore(Snapshot(createDesktop: nil), expecting: Self.hiddenApplied)

        #expect(await defaults.calls == [.read(Self.key), .remove(Self.key)])
        #expect(await defaults.values.isEmpty)
    }

    // Per-action scenario: restore skips when changed
    @Test
    func restoreSkipsWhenTheUserChangedTheValue() async throws {
        let (action, defaults) = makeAction(.bool(true))

        let outcome = try await action.restore(Snapshot(createDesktop: nil), expecting: Self.hiddenApplied)

        #expect(outcome == .skippedBecauseChangedByUser)
        #expect(await defaults.calls == [.read(Self.key)])
        #expect(await processRunner.commands.isEmpty)
    }

    @Test
    func restoreWithoutAppliedStateRestoresUnconditionally() async throws {
        let (action, defaults) = makeAction(.bool(true))

        let outcome = try await action.restore(Snapshot(createDesktop: nil), expecting: nil)

        #expect(outcome == .restored)
        #expect(await defaults.values[Self.key] == nil)
        #expect(await processRunner.commands == [Self.killallFinder])
    }

    @Test
    func restoreWhenAlreadyAtTheSnapshotDoesNothing() async throws {
        let (action, defaults) = makeAction(.bool(false))

        let outcome = try await action.restore(Snapshot(createDesktop: .bool(false)), expecting: nil)

        #expect(outcome == .restored)
        #expect(await defaults.calls == [.read(Self.key)])
        #expect(await processRunner.commands.isEmpty)
    }

    @Test
    func restoreFailsWhenTheValueCannotBeRead() async {
        let (action, defaults) = makeAction(.bool(false))
        await defaults.failNext(.read, with: DefaultsError.unsupportedValueType(Self.key))

        await #expect(throws: DefaultsError.unsupportedValueType(Self.key)) {
            try await action.restore(Snapshot(createDesktop: nil), expecting: nil)
        }
    }

    @Test
    func restoreFailsWhenFinderRestartTimesOut() async {
        let (action, _) = makeAction(.bool(false))
        await processRunner.script(Self.killallFinder, .failure(ProcessError.timedOut(.seconds(10))))

        await #expect(throws: ProcessError.timedOut(.seconds(10))) {
            try await action.restore(Snapshot(createDesktop: nil), expecting: nil)
        }
    }
}
