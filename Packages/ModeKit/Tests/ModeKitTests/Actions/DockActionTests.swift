import Foundation
import ModeKit
import Testing

struct DockActionTests {
    private static let key = DefaultsKey(domain: "com.apple.dock", name: "autohide")
    private static let enable = AppleScript(
        "tell application \"System Events\" to set autohide of dock preferences to true")
    private static let disable = AppleScript(
        "tell application \"System Events\" to set autohide of dock preferences to false")
    private static let onApplied = DockAction.AppliedState(autohide: .bool(true))
    private typealias Snapshot = DockAction.Snapshot

    private struct Fixture {
        let action: DockAction
        let defaults: FakeDefaultsStore
        let scripts: FakeAppleScriptRunner
    }

    private enum ScriptEffect {
        /// Scripts write the key as System Events did in spike S4.
        case systemEventsAsObserved
        /// Scripts succeed but change nothing.
        case none
    }

    private func makeFixture(
        _ initial: DefaultsValue?,
        scriptEffect: ScriptEffect = .systemEventsAsObserved,
    ) -> Fixture {
        let defaults = FakeDefaultsStore(initial.map { [Self.key: $0] } ?? [:])
        let systemEvents = scriptEffect == .systemEventsAsObserved ? defaults : nil
        let scripts = FakeAppleScriptRunner(systemEvents: systemEvents)
        let action = DockAction(defaults: defaults, appleScriptRunner: scripts)
        return Fixture(action: action, defaults: defaults, scripts: scripts)
    }

    // Per-action scenario: capture reads current state
    @Test(arguments: [nil, DefaultsValue.bool(true), .bool(false)])
    func captureReadsTheKeyAndRunsNoScript(initial: DefaultsValue?) async throws {
        let fixture = makeFixture(initial)

        #expect(try await fixture.action.capture() == Snapshot(autohide: initial))
        #expect(await fixture.defaults.calls == [.read(Self.key)])
        #expect(await fixture.scripts.scripts.isEmpty)
    }

    // Per-action scenario: apply sets the expected state
    @Test(arguments: [nil, DefaultsValue.bool(false)])
    func applyRunsTheEnableScriptAndReadsTrueBack(initial: DefaultsValue?) async throws {
        let fixture = makeFixture(initial)

        #expect(try await fixture.action.apply() == Self.onApplied)
        #expect(await fixture.scripts.scripts == [Self.enable])
        #expect(await fixture.scripts.timeouts == [.seconds(130)])
        #expect(await fixture.defaults.calls == [.read(Self.key), .read(Self.key)])
    }

    // Per-action scenario: state already equal to the target
    @Test
    func alreadyAutoHiddenRunsNoScriptOnApplyOrRestore() async throws {
        let fixture = makeFixture(.bool(true))

        let applied = try await fixture.action.apply()
        let outcome = try await fixture.action.restore(Snapshot(autohide: .bool(true)), expecting: applied)

        #expect(outcome == .restored)
        #expect(await fixture.scripts.scripts.isEmpty)
        #expect(await fixture.defaults.values == [Self.key: .bool(true)])
    }

    // Per-action scenario: the system call fails, and timeout
    @Test(arguments: [AppleScriptError.notAuthorized, .timedOut])
    func scriptFailureFailsTheApply(error: AppleScriptError) async {
        let fixture = makeFixture(nil)
        await fixture.scripts.fail(Self.enable, with: error)

        await #expect(throws: error) { try await fixture.action.apply() }
        #expect(await fixture.defaults.values.isEmpty)
    }

    @Test
    func scriptThatDoesNotChangeTheKeyFailsWithTheObservedValue() async {
        let fixture = makeFixture(.bool(false), scriptEffect: .none)

        await #expect(throws: DockActionError.settingNotApplied(observed: .bool(false))) {
            try await fixture.action.apply()
        }
        #expect(
            DockActionError.settingNotApplied(observed: nil).description
                == "Dock auto-hide was not applied; autohide reads absent"
        )
    }

    @Test
    func defaultsReadFailureFailsCaptureAndApply() async {
        let fixture = makeFixture(nil)
        let failure = DefaultsError.failed(reason: "cfprefsd unavailable")

        await fixture.defaults.failNext(.read, with: failure)
        await #expect(throws: failure) { try await fixture.action.capture() }
        await fixture.defaults.failNext(.read, with: failure)
        await #expect(throws: failure) { try await fixture.action.apply() }
        #expect(await fixture.scripts.scripts.isEmpty)
    }

    // Per-action scenario: restore returns to the captured state
    @Test
    func keyAbsentAtCaptureIsRemovedAfterTheScriptWritesFalse() async throws {
        let fixture = makeFixture(nil)
        let applied = try await fixture.action.apply()

        let outcome = try await fixture.action.restore(Snapshot(autohide: nil), expecting: applied)

        #expect(outcome == .restored)
        #expect(await fixture.scripts.scripts == [Self.enable, Self.disable])
        #expect(await fixture.defaults.calls.suffix(3) == [.read(Self.key), .read(Self.key), .remove(Self.key)])
        #expect(await fixture.defaults.values.isEmpty)
    }

    @Test
    func capturedFalseIsRestoredByTheScriptWithoutAnExtraWrite() async throws {
        let fixture = makeFixture(.bool(false))
        let applied = try await fixture.action.apply()

        _ = try await fixture.action.restore(Snapshot(autohide: .bool(false)), expecting: applied)

        #expect(await fixture.defaults.values == [Self.key: .bool(false)])
        #expect(await !fixture.defaults.calls.contains { if case .write = $0 { true } else { false } })
    }

    // Per-action scenario: restore skips when changed
    @Test
    func restoreSkipsWhenTheUserChangedAutohide() async throws {
        let fixture = makeFixture(.bool(false))

        let outcome = try await fixture.action.restore(Snapshot(autohide: nil), expecting: Self.onApplied)

        #expect(outcome == .skippedBecauseChangedByUser)
        #expect(await fixture.scripts.scripts.isEmpty)
        #expect(await fixture.defaults.values == [Self.key: .bool(false)])
    }

    @Test
    func restoreWithoutAppliedStateRestoresUnconditionally() async throws {
        let fixture = makeFixture(.bool(true))

        let outcome = try await fixture.action.restore(Snapshot(autohide: nil), expecting: nil)

        #expect(outcome == .restored)
        #expect(await fixture.scripts.scripts == [Self.disable])
        #expect(await fixture.defaults.values.isEmpty)
    }

    @Test
    func nonBooleanCapturedValueIsWrittenBackWithItsTypeAfterTheScript() async throws {
        let fixture = makeFixture(.integer(1))
        let applied = try await fixture.action.apply()

        _ = try await fixture.action.restore(Snapshot(autohide: .integer(1)), expecting: applied)

        #expect(await fixture.scripts.scripts == [Self.enable, Self.disable])
        #expect(await fixture.defaults.values == [Self.key: .integer(1)])
    }

    @Test(arguments: [AppleScriptError.notAuthorized, .timedOut])
    func scriptFailureFailsTheRestoreAndLeavesTheKey(error: AppleScriptError) async {
        let fixture = makeFixture(.bool(true))
        await fixture.scripts.fail(Self.disable, with: error)

        await #expect(throws: error) {
            try await fixture.action.restore(Snapshot(autohide: nil), expecting: Self.onApplied)
        }
        #expect(await fixture.defaults.values == [Self.key: .bool(true)])
    }
}
