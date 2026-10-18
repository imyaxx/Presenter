import ModeKit
import Testing

/// End-to-end: the real session controller over the desktop icons, Dock, menu bar and hide apps actions.
@Suite(.timeLimit(.minutes(1)))
struct FourStepSessionTests {
    private typealias Harness = StandardActionsHarness

    enum InitialWorld: CaseIterable, Sendable {
        /// Every key absent; two visible applications, a frontmost one and this application.
        case factory
        /// Menu bar keys written explicitly by System Settings ("In Full Screen Only"), Dock auto-hide on, desktop
        /// icons shown explicitly; one application already hidden and one excluded.
        case setBySystemSettings
        /// Every key at the target and no application to hide.
        case alreadyAtTarget
    }

    private let mail: BundleIdentifier
    private let notes: BundleIdentifier
    private let safari: BundleIdentifier
    private let terminal: BundleIdentifier
    private let presenter: BundleIdentifier
    private let music: BundleIdentifier
    private let profile: Profile

    init() throws {
        mail = try BundleIdentifier("com.example.mail")
        notes = try BundleIdentifier("com.example.notes")
        safari = try BundleIdentifier("com.example.safari")
        terminal = try BundleIdentifier("com.example.terminal")
        presenter = try BundleIdentifier("com.example.presenter")
        music = try BundleIdentifier("com.example.music")
        profile = Harness.fourStepProfile(excluding: [music])
    }

    private func makeHarness(_ world: InitialWorld) async -> Harness {
        let others: [RunningApplication] = [
            .fixture(terminal, role: .frontmost), .fixture(presenter, role: .thisApplication),
        ]
        switch world {
        case .factory:
            return await Harness(initial: [:], applications: [.fixture(mail), .fixture(notes)] + others)
        case .setBySystemSettings:
            let values: [DefaultsKey: DefaultsValue] = [
                Harness.createDesktop: .bool(true),
                Harness.autohide: .bool(true),
                Harness.menuBarOption: .integer(2),
                Harness.hideMenuBar: .bool(false),
                Harness.menuBarInFullscreen: .bool(false),
            ]
            let applications: [RunningApplication] = [.fixture(mail), .fixture(safari, .hidden), .fixture(music)]
            return await Harness(initial: values, applications: applications + others)
        case .alreadyAtTarget:
            let values: [DefaultsKey: DefaultsValue] = [
                Harness.createDesktop: .bool(false),
                Harness.autohide: .bool(true),
                Harness.menuBarOption: .integer(0),
                Harness.hideMenuBar: .bool(true),
                Harness.menuBarInFullscreen: .bool(false),
            ]
            return await Harness(initial: values, applications: [.fixture(safari, .hidden)] + others)
        }
    }

    private static let allRestored = RestoreReport(
        restored: [.hideApps, .menuBar, .dock, .desktopIcons],
        skippedBecauseChangedByUser: [],
        failed: [],
    )

    // (a)
    @Test(arguments: InitialWorld.allCases)
    func activateThenDeactivateLeavesTheSystemExactlyAsItWas(world: InitialWorld) async throws {
        let harness = await makeHarness(world)
        let initialValues = await harness.defaults.values
        let initialApplications = await harness.workspace.applications
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()

        _ = try await controller.activate(profile)
        let report = try await controller.deactivate()

        #expect(report == .performed(Self.allRestored))
        #expect(await harness.defaults.values == initialValues)
        #expect(await harness.workspace.applications == initialApplications)
        #expect(await harness.notifier.posts.count == (world == .alreadyAtTarget ? 0 : 2))
        #expect(await harness.sessionFile() == nil)
    }

    // (b)
    @Test
    func aMenuBarWriteFailingAtTheLastStepRollsBackEveryEarlierStep() async throws {
        let harness = await makeHarness(.setBySystemSettings)
        let initialValues = await harness.defaults.values
        let initialApplications = await harness.workspace.applications
        await harness.defaults.failNext(.write, for: Harness.hideMenuBar, with: DefaultsError.failed(reason: "denied"))
        let menuBarLast = ProfileBuilder(steps: [
            .hideDesktopIcons, .hideDock, .hideApps(exclusions: [music]), .hideMenuBar,
        ]).build()
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()

        await #expect {
            try await controller.activate(menuBarLast)
        } throws: { error in
            guard case .applyFailed(let failure, let rollback) = error as? SessionError else {
                return false
            }
            return failure.identifier == .menuBar && rollback.failed.isEmpty
                && rollback.restored == [.menuBar, .hideApps, .dock, .desktopIcons]
        }

        #expect(await harness.defaults.values == initialValues)
        #expect(await harness.workspace.applications == initialApplications)
        #expect(await harness.notifier.posts == [.menuBarHidingChanged])
        #expect(await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }

    // (c)
    @Test
    func crashRecoveryRestoresEverythingFromTheSessionFileAlone() async throws {
        let harness = await makeHarness(.setBySystemSettings)
        let initialValues = await harness.defaults.values
        let initialApplications = await harness.workspace.applications
        let crashed = harness.makeController()
        _ = await crashed.recoverIfNeeded()
        _ = try await crashed.activate(profile)
        #expect(await harness.workspace.applications.filter(\.isHidden).count == 2)

        let relaunched = harness.makeController()
        let outcome = await relaunched.recoverIfNeeded()

        #expect(outcome == .restored(Self.allRestored))
        #expect(await harness.defaults.values == initialValues)
        #expect(await harness.workspace.applications == initialApplications)
        #expect(await harness.sessionFile() == nil)
    }

    // (d)
    @Test
    func userChangesToTheMenuBarAndOneApplicationAreKept() async throws {
        let harness = await makeHarness(.factory)
        let initialApplications = await harness.workspace.applications
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()
        _ = try await controller.activate(profile)
        let userChoice: [DefaultsKey: DefaultsValue] = [
            Harness.menuBarOption: .integer(3),
            Harness.menuBarInFullscreen: .bool(true),
        ]
        await harness.defaults.place(.integer(3), for: Harness.menuBarOption)
        await harness.defaults.place(nil, for: Harness.hideMenuBar)
        await harness.defaults.place(.bool(true), for: Harness.menuBarInFullscreen)
        await harness.workspace.userUnhides(mail)

        let report = try await controller.deactivate()

        #expect(
            report
                == .performed(
                    RestoreReport(
                        restored: [.hideApps, .dock, .desktopIcons],
                        skippedBecauseChangedByUser: [.menuBar],
                        failed: [],
                    )))
        #expect(await harness.defaults.values == userChoice)
        #expect(await harness.workspace.applications == initialApplications)
        #expect(await harness.workspace.calls.last == .unhide(notes))
    }

    @Test
    func aRefusedUnhideDegradesTheSessionAndARetrySucceedsOnceAllowed() async throws {
        let harness = await makeHarness(.factory)
        let initialApplications = await harness.workspace.applications
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()
        _ = try await controller.activate(profile)
        await harness.workspace.refuse(.unhide, of: mail)

        let report = try await controller.deactivate()

        let failure = ActionFailure(identifier: .hideApps, error: HideAppsActionError.couldNotUnhide([mail]))
        let expected = RestoreReport(
            restored: [.menuBar, .dock, .desktopIcons],
            skippedBecauseChangedByUser: [],
            failed: [failure],
        )
        #expect(report == .performed(expected))
        guard case .degraded(.restoreFailed) = await controller.state else {
            Issue.record("expected degraded")
            return
        }
        #expect(await harness.workspace.applications == [.fixture(mail, .hidden)] + initialApplications.dropFirst())

        await harness.workspace.allow(.unhide, of: mail)
        let retry = await controller.retryRestore()

        let restoredHideApps = RestoreReport(restored: [.hideApps], skippedBecauseChangedByUser: [], failed: [])
        #expect(retry == .performed(.restored(restoredHideApps)))
        #expect(await harness.workspace.applications == initialApplications)
        #expect(await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }
}
