import Foundation
import ModeKit
import Testing

/// End-to-end: the real session controller over the desktop icons and Dock actions.
@Suite(.timeLimit(.minutes(1)))
struct DesktopIconsAndDockSessionTests {
    private typealias Harness = StandardActionsHarness

    struct InitialState: Sendable, CustomTestStringConvertible {
        let name: String
        let values: [DefaultsKey: DefaultsValue]
        let expectedFinderRestarts: Int
        let expectedScripts: Int
        var testDescription: String { name }
    }

    static let initialStates = [
        InitialState(name: "both keys absent", values: [:], expectedFinderRestarts: 2, expectedScripts: 2),
        InitialState(
            name: "both keys present",
            values: [Harness.createDesktop: .bool(true), Harness.autohide: .bool(false)],
            expectedFinderRestarts: 2,
            expectedScripts: 2,
        ),
        InitialState(
            name: "icons hidden and Dock auto-hidden already",
            values: [Harness.createDesktop: .bool(false), Harness.autohide: .bool(true)],
            expectedFinderRestarts: 0,
            expectedScripts: 0,
        ),
    ]

    // (a)
    @Test(arguments: initialStates)
    func activateThenDeactivateLeavesThePreferencesExactlyAsTheyWere(initial: InitialState) async throws {
        let harness = Harness(initial: initial.values)
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()

        _ = try await controller.activate(Harness.profile)
        let report = try await controller.deactivate()

        #expect(
            report
                == .performed(
                    RestoreReport(restored: [.dock, .desktopIcons], skippedBecauseChangedByUser: [], failed: [])))
        #expect(await harness.defaults.values == initial.values)
        #expect(await harness.processRunner.commands.count == initial.expectedFinderRestarts)
        #expect(await harness.scripts.scripts.count == initial.expectedScripts)
        #expect(await harness.sessionFile() == nil)
    }

    // (b)
    @Test
    func dockNotAuthorizedRollsBackTheDesktopIcons() async throws {
        let harness = Harness(initial: [:])
        await harness.scripts.fail(
            AppleScript("tell application \"System Events\" to set autohide of dock preferences to true"),
            with: AppleScriptError.notAuthorized,
        )
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()

        await #expect {
            try await controller.activate(Harness.profile)
        } throws: { error in
            guard case .applyFailed(let failure, let rollback) = error as? SessionError else {
                return false
            }
            return failure.identifier == .dock && rollback.restored == [.dock, .desktopIcons] && rollback.failed.isEmpty
        }

        #expect(await harness.defaults.values.isEmpty)
        #expect(await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }

    // (c)
    @Test
    func crashRecoveryRestoresFromTheSessionFileAlone() async throws {
        let initial: [DefaultsKey: DefaultsValue] = [Harness.createDesktop: .integer(1)]
        let harness = Harness(initial: initial)
        let crashed = harness.makeController()
        _ = await crashed.recoverIfNeeded()
        _ = try await crashed.activate(Harness.profile)
        #expect(await harness.sessionFile() != nil)

        let relaunched = harness.makeController()
        let outcome = await relaunched.recoverIfNeeded()

        #expect(
            outcome
                == .restored(
                    RestoreReport(restored: [.dock, .desktopIcons], skippedBecauseChangedByUser: [], failed: [])))
        #expect(await harness.defaults.values == initial)
        #expect(await harness.sessionFile() == nil)
    }

    // (d)
    @Test
    func userChangeToTheDockDuringTheSessionIsKept() async throws {
        let harness = Harness(initial: [:])
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()
        _ = try await controller.activate(Harness.profile)
        await harness.defaults.place(.bool(false), for: Harness.autohide)

        let report = try await controller.deactivate()

        #expect(
            report
                == .performed(
                    RestoreReport(restored: [.desktopIcons], skippedBecauseChangedByUser: [.dock], failed: [])))
        #expect(await harness.defaults.values == [Harness.autohide: .bool(false)])
    }

    @Test
    func dockNotAuthorizedOnRestoreDegradesAndKeepsItsRecord() async throws {
        let harness = Harness(initial: [:])
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()
        _ = try await controller.activate(Harness.profile)
        await harness.scripts.fail(
            AppleScript("tell application \"System Events\" to set autohide of dock preferences to false"),
            with: AppleScriptError.notAuthorized,
        )

        let report = try await controller.deactivate()

        guard case .performed(let restoreReport) = report else {
            Issue.record("deactivate was ignored")
            return
        }
        #expect(restoreReport.restored == [.desktopIcons])
        #expect(restoreReport.failed.map(\.identifier) == [.dock])
        guard case .degraded(.restoreFailed) = await controller.state else {
            Issue.record("expected degraded")
            return
        }
        #expect(await harness.sessionFile() != nil)
    }
}
