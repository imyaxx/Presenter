import Foundation
import ModeKit
import Testing

/// End-to-end: the real session controller over all five actions, the last one being the wallpaper.
@Suite(.timeLimit(.minutes(1)))
struct FiveStepSessionTests {
    private typealias Harness = StandardActionsHarness

    enum InitialWorld: CaseIterable, Sendable {
        /// Every key absent; two visible applications; one display with a custom color.
        case factory
        /// Keys written by System Settings, Dock auto-hide on, desktop icons shown explicitly; one application already
        /// hidden and one excluded; two displays, one with a dynamic wallpaper and one with a still image.
        case setBySystemSettings
    }

    private static let killallFinder = ProcessCommand(
        executableURL: URL(filePath: "/usr/bin/killall"),
        arguments: ["Finder"],
        timeout: .seconds(10),
    )
    private static let killallWallpaperAgent = ProcessCommand(
        executableURL: URL(filePath: "/usr/bin/killall"),
        arguments: ["WallpaperAgent"],
        timeout: .seconds(10),
    )
    private static let left = DisplayIdentifier(
        uuid: UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID())
    private static let right = DisplayIdentifier(
        uuid: UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID())
    private static let blue = SolidColor(red: 0x1E, green: 0x90, blue: 0xFF)
    private static let allRestored = RestoreReport(
        restored: [.wallpaper, .hideApps, .menuBar, .dock, .desktopIcons],
        skippedBecauseChangedByUser: [],
        failed: [],
    )

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
        profile = Harness.fiveStepProfile(
            excluding: [music],
            wallpaper: .solidColor(Self.blue),
            displays: .allDisplays,
        )
    }

    private func makeHarness(_ world: InitialWorld) async -> Harness {
        let others: [RunningApplication] = [
            .fixture(terminal, role: .frontmost), .fixture(presenter, role: .thisApplication),
        ]
        switch world {
        case .factory:
            return await Harness(
                initial: [:],
                applications: [.fixture(mail), .fixture(notes)] + others,
                wallpapers: [Self.left: "color 0.0823 0.0823 0.0823"],
            )
        case .setBySystemSettings:
            let values: [DefaultsKey: DefaultsValue] = [
                Harness.createDesktop: .bool(true),
                Harness.autohide: .bool(true),
                Harness.menuBarOption: .integer(2),
                Harness.hideMenuBar: .bool(false),
                Harness.menuBarInFullscreen: .bool(false),
            ]
            return await Harness(
                initial: values,
                applications: [.fixture(mail), .fixture(safari, .hidden), .fixture(music)] + others,
                wallpapers: [
                    Self.left: "dynamic com.apple.wallpaper.choice.sequoia",
                    Self.right: "image /Users/someone/Pictures/photo.jpg",
                ],
            )
        }
    }

    /// Dock scripts expected for a full session: on and off when auto-hide starts off, none when it is already on.
    private func expectedScriptCount(_ world: InitialWorld) -> Int {
        switch world {
        case .factory: 2
        case .setBySystemSettings: 0
        }
    }

    // (a)
    @Test(arguments: InitialWorld.allCases)
    func activateThenDeactivateLeavesTheSystemExactlyAsItWas(world: InitialWorld) async throws {
        let harness = await makeHarness(world)
        let initialValues = await harness.defaults.values
        let initialApplications = await harness.workspace.applications
        let initialStore = await harness.wallpaperStoreData()
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()

        _ = try await controller.activate(profile)
        #expect(await harness.wallpaperStoreData() != initialStore)
        let report = try await controller.deactivate()

        #expect(report == .performed(Self.allRestored))
        #expect(await harness.defaults.values == initialValues)
        #expect(await harness.workspace.applications == initialApplications)
        #expect(await harness.wallpaperStoreData() == initialStore)
        let expectedCommands = [Self.killallFinder, Self.killallWallpaperAgent, Self.killallFinder]
        #expect(await harness.processRunner.commands == expectedCommands)
        #expect(await harness.scripts.scripts.count == expectedScriptCount(world))
        #expect(await harness.imageRenderer.colors == [Self.blue])
        #expect(await harness.sessionFile() == nil)
    }

    // (b)
    @Test
    func aWallpaperStoreThatNeverChangesRollsBackEveryStep() async throws {
        let harness = await makeHarness(.setBySystemSettings)
        let initialValues = await harness.defaults.values
        let initialApplications = await harness.workspace.applications
        let initialStore = await harness.wallpaperStoreData()
        await harness.wallpaperStore.persist(.never)
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()

        await #expect {
            try await controller.activate(profile)
        } throws: { error in
            guard case .applyFailed(let failure, let rollback) = error as? SessionError else {
                return false
            }
            return failure == ActionFailure(identifier: .wallpaper, error: WallpaperActionError.storeDidNotChange)
                && rollback == Self.allRestored
        }

        #expect(harness.actionClock.sleeps.count == 50)
        #expect(await harness.defaults.values == initialValues)
        #expect(await harness.workspace.applications == initialApplications)
        #expect(await harness.wallpaperStoreData() == initialStore)
        #expect(await harness.sessionFile() == nil)
        #expect(await controller.state == .idle)
    }

    // (c)
    @Test
    func crashRecoveryRestoresTheWallpaperStoreFromTheSessionFileAlone() async throws {
        let harness = await makeHarness(.setBySystemSettings)
        let initialValues = await harness.defaults.values
        let initialApplications = await harness.workspace.applications
        let initialStore = await harness.wallpaperStoreData()
        let crashed = harness.makeController()
        _ = await crashed.recoverIfNeeded()
        _ = try await crashed.activate(profile)
        #expect(await harness.wallpaperStoreData() != initialStore)

        let relaunched = harness.makeController()
        let outcome = await relaunched.recoverIfNeeded()

        #expect(outcome == .restored(Self.allRestored))
        #expect(await harness.wallpaperStoreData() == initialStore)
        #expect(await harness.defaults.values == initialValues)
        #expect(await harness.workspace.applications == initialApplications)
        #expect(await harness.processRunner.commands.last == Self.killallFinder)
        #expect(await harness.processRunner.commands.contains(Self.killallWallpaperAgent))
        #expect(await harness.sessionFile() == nil)
    }

    // (d)
    @Test
    func aWallpaperTheUserChoseDuringTheSessionIsKept() async throws {
        let harness = await makeHarness(.factory)
        let initialValues = await harness.defaults.values
        let controller = harness.makeController()
        _ = await controller.recoverIfNeeded()
        _ = try await controller.activate(profile)
        await harness.wallpaperStore.userSets("dynamic com.apple.wallpaper.choice.sequoia", on: Self.left)

        let report = try await controller.deactivate()

        let expected = RestoreReport(
            restored: [.hideApps, .menuBar, .dock, .desktopIcons],
            skippedBecauseChangedByUser: [.wallpaper],
            failed: [],
        )
        #expect(report == .performed(expected))
        #expect(await harness.wallpaperStore.wallpapers() == [Self.left: "dynamic com.apple.wallpaper.choice.sequoia"])
        #expect(await !harness.processRunner.commands.contains(Self.killallWallpaperAgent))
        #expect(await harness.defaults.values == initialValues)
    }
}
