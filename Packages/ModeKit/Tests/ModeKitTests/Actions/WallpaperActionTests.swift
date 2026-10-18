import Foundation
import Testing

@testable import ModeKit

@Suite(.timeLimit(.minutes(1)))
struct WallpaperActionTests {
    private static let locations = StandardActionsHarness.wallpaperLocations
    private static let left = DisplayIdentifier(
        uuid: UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID())
    private static let right = DisplayIdentifier(
        uuid: UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID())
    private static let missing = DisplayIdentifier(
        uuid: UUID(uuidString: "33333333-3333-4333-8333-333333333333") ?? UUID())
    private static let gray = "color 0.0823 0.0823 0.0823"
    private static let blue = SolidColor(red: 0x1E, green: 0x90, blue: 0xFF)
    private static let blueImage = locations.generatedImagesDirectory.appending(path: "solid-1e90ff.png")
    private static let photo = URL(filePath: "/Users/someone/Pictures/plain.png")

    private struct Fixture {
        let action: WallpaperAction
        let files: InMemoryFileStore
        let store: FakeWallpaperStore
        let workspace: FakeWorkspaceAdapter
        let renderer: FakeSolidColorImageRenderer
        let clock: FakeClock
    }

    private func makeFixture(
        _ choice: WallpaperChoice = .solidColor(blue),
        on selection: DisplaySelection = .allDisplays,
        connected: [DisplayIdentifier] = [left, right],
        inspector: FakeWallpaperStoreInspector = FakeWallpaperStoreInspector(),
        clock: FakeClock = FakeClock(sleeping: .immediate),
    ) async -> Fixture {
        let files = InMemoryFileStore()
        let wallpapers = Dictionary(uniqueKeysWithValues: connected.map { ($0, Self.gray) })
        let store = await FakeWallpaperStore.make(in: files, at: Self.locations.storeURL, wallpapers: wallpapers)
        let workspace = FakeWorkspaceAdapter(displays: connected, wallpaperStore: store)
        let renderer = FakeSolidColorImageRenderer()
        let ports = ActionPorts(
            defaults: FakeDefaultsStore(),
            processRunner: FakeProcessRunner(),
            appleScriptRunner: FakeAppleScriptRunner(),
            workspace: workspace,
            notifier: FakeDistributedNotifier(),
            fileStore: files,
            clock: clock,
            imageRenderer: renderer,
            storeInspector: inspector,
        )
        let action = WallpaperAction(choice: choice, displays: selection, ports: ports, locations: Self.locations)
        return Fixture(
            action: action,
            files: files,
            store: store,
            workspace: workspace,
            renderer: renderer,
            clock: clock,
        )
    }

    private func fingerprint(_ fixture: Fixture) async throws -> WallpaperStoreFingerprint {
        try FakeWallpaperStoreInspector().fingerprint(
            of: await fixture.files.contents(of: Self.locations.storeURL) ?? Data())
    }

    // Per-action scenario: capture reads current state
    @Test
    func captureReadsTheStoreBytesAndChangesNothing() async throws {
        let fixture = await makeFixture()
        let before = await fixture.files.contents(of: Self.locations.storeURL)

        let snapshot = try await fixture.action.capture()

        #expect(snapshot.storeData == before)
        #expect(await fixture.files.operations == [.read("Index.plist")])
        #expect(await fixture.workspace.calls.isEmpty)
    }

    @Test
    func aMissingStoreFailsCaptureAndApplyBeforeAnyChange() async throws {
        let fixture = await makeFixture()
        try await fixture.files.remove(Self.locations.storeURL)

        await #expect(throws: WallpaperActionError.storeUnavailable) { try await fixture.action.capture() }
        await #expect(throws: WallpaperActionError.storeUnavailable) { try await fixture.action.apply() }
        #expect(await fixture.workspace.calls.isEmpty)
        #expect(await fixture.renderer.colors.isEmpty)
    }

    // Per-action scenario: apply sets the expected state
    @Test
    func aSolidColorIsRenderedOnceWrittenAndSetOnEverySelectedDisplay() async throws {
        let fixture = await makeFixture()

        let applied = try await fixture.action.apply()

        #expect(await fixture.renderer.colors == [Self.blue])
        #expect(await fixture.files.contents(of: Self.blueImage) == FakeSolidColorImageRenderer.bytes(for: Self.blue))
        let setCalls = await fixture.workspace.calls.dropFirst()
        #expect(
            Array(setCalls) == [
                .setDesktopImage(Self.blueImage, Self.left), .setDesktopImage(Self.blueImage, Self.right),
            ])
        #expect(applied.displays == [Self.left, Self.right])
        #expect(applied.fingerprint == (try await fingerprint(fixture)))
        let expected = "image \(Self.blueImage.path(percentEncoded: false))"
        #expect(await fixture.store.wallpapers() == [Self.left: expected, Self.right: expected])
    }

    @Test
    func theGeneratedImageIsNamedWithLowercaseTwoDigitHex() {
        #expect(
            WallpaperAction.generatedImageName(for: SolidColor(red: 0x0A, green: 0xFF, blue: 0)) == "solid-0aff00.png")
    }

    @Test
    func anImageIsPassedThroughUnchangedAndNothingIsRendered() async throws {
        let fixture = await makeFixture(.image(Self.photo))

        _ = try await fixture.action.apply()

        #expect(await fixture.renderer.colors.isEmpty)
        #expect(
            await fixture.workspace.calls.dropFirst().elementsEqual([
                .setDesktopImage(Self.photo, Self.left), .setDesktopImage(Self.photo, Self.right),
            ]))
        #expect(await !fixture.files.operations.contains { if case .write = $0 { true } else { false } })
    }

    @Test
    func allDisplaysWithOneDisplay() async throws {
        let fixture = await makeFixture(connected: [Self.left])

        #expect(try await fixture.action.apply().displays == [Self.left])
    }

    @Test
    func aSelectedDisplayThatIsNotConnectedIsSkipped() async throws {
        let fixture = await makeFixture(on: .specific([Self.right, Self.missing]))

        let applied = try await fixture.action.apply()

        #expect(applied.displays == [Self.right])
        #expect(await fixture.workspace.calls == [.connectedDisplays, .setDesktopImage(Self.blueImage, Self.right)])
    }

    // Per-action scenario: state already equal to the target (nothing to change)
    @Test
    func noSelectedDisplayConnectedChangesNothing() async throws {
        let fixture = await makeFixture(on: .specific([Self.missing]))
        let before = try await fingerprint(fixture)

        let applied = try await fixture.action.apply()

        #expect(applied == WallpaperAction.AppliedState(displays: [], fingerprint: before))
        #expect(await fixture.workspace.calls == [.connectedDisplays])
        #expect(await fixture.files.operations == [.read("Index.plist")])
        #expect(await fixture.renderer.colors.isEmpty)
        #expect(fixture.clock.sleeps.isEmpty)
    }

    @Test
    func theTargetAlreadyBeingTheCurrentWallpaperFailsTheApply() async throws {
        let fixture = await makeFixture(.image(Self.photo), connected: [Self.left])
        await fixture.store.userSets("image \(Self.photo.path(percentEncoded: false))", on: Self.left)

        await #expect(throws: WallpaperActionError.storeDidNotChange) { try await fixture.action.apply() }
        #expect(fixture.clock.sleeps.count == 50)
    }

    // Per-action scenario: the system call fails
    @Test(arguments: [
        WallpaperStoreError.unrecognizedFormat(reason: "scripted"),
        .unrecognizedFormat(reason: "new macOS format"),
    ])
    func anInspectorFailureFailsTheApplyBeforeAnyChange(error: WallpaperStoreError) async throws {
        let fixture = await makeFixture(inspector: FakeWallpaperStoreInspector(failure: error))

        await #expect(throws: error) { try await fixture.action.apply() }
        #expect(await fixture.workspace.calls.isEmpty)
        #expect(await fixture.renderer.colors.isEmpty)
        #expect(await fixture.files.operations == [.read("Index.plist")])
    }

    @Test
    func anUnrecognizedStoreFailsTheApplyBeforeAnyChange() async throws {
        let fixture = await makeFixture()
        await fixture.files.place(Data("<?xml version=\"1.0\"?><plist/>".utf8), at: Self.locations.storeURL)

        await #expect(throws: WallpaperStoreError.unrecognizedFormat(reason: "missing header")) {
            try await fixture.action.apply()
        }
        #expect(await fixture.workspace.calls.isEmpty)
    }

    @Test(arguments: [left, right])
    func aFailingSetDesktopImageFailsTheApplyWithoutPolling(failing display: DisplayIdentifier) async throws {
        let fixture = await makeFixture()
        let error = FakeWorkspaceAdapter.DisplayNotConnected(display: display)
        await fixture.workspace.failSetDesktopImage(on: display, with: error)

        await #expect(throws: error) {
            try await fixture.action.apply()
        }
        #expect(await fixture.workspace.calls.last == .setDesktopImage(Self.blueImage, display))
        #expect(fixture.clock.sleeps.isEmpty)
    }

    @Test
    func aRendererFailureFailsTheApplyBeforeAnyImageIsSet() async throws {
        let fixture = await makeFixture()
        await fixture.renderer.fail(with: InMemoryFileStore.InjectedFailure())

        await #expect(throws: InMemoryFileStore.InjectedFailure()) { try await fixture.action.apply() }
        #expect(await fixture.workspace.calls == [.connectedDisplays])
    }

    @Test
    func aFailingPNGWriteFailsTheApplyBeforeAnyImageIsSet() async throws {
        let fixture = await makeFixture()
        await fixture.files.failNextWrite()

        await #expect(throws: InMemoryFileStore.InjectedFailure()) { try await fixture.action.apply() }
        #expect(await fixture.workspace.calls == [.connectedDisplays])
        #expect(await fixture.files.contents(of: Self.blueImage) == nil)
    }

    // Per-action scenario: timeout (the polling window)
    @Test(arguments: [(0, 1), (3, 4)])
    func pollingEndsWhenTheStoreChanges(readsBeforePersist: Int, expectedPolls: Int) async throws {
        let fixture = await makeFixture()
        await fixture.store.persist(.afterReads(readsBeforePersist))

        let applied = try await fixture.action.apply()

        #expect(fixture.clock.sleeps == Array(repeating: .milliseconds(100), count: expectedPolls))
        #expect(applied.fingerprint == (try await fingerprint(fixture)))
    }

    @Test
    func aStoreThatNeverChangesFailsAfterFiftyPolls() async throws {
        let fixture = await makeFixture()
        await fixture.store.persist(.never)

        await #expect(throws: WallpaperActionError.storeDidNotChange) { try await fixture.action.apply() }
        #expect(fixture.clock.sleeps == Array(repeating: .milliseconds(100), count: 50))
        let storeReads = await fixture.files.operations.filter { $0 == .read("Index.plist") }
        #expect(storeReads.count == 51)
    }

    @Test
    func cancellationDuringPollingStopsTheApply() async throws {
        let fixture = await makeFixture(clock: FakeClock())
        await fixture.store.persist(.never)
        let apply = Task { try await fixture.action.apply() }

        await fixture.clock.waitForSleeper()
        apply.cancel()

        await #expect(throws: CancellationError.self) { try await apply.value }
    }

    // Edge case: display disconnected between capture and restore
    @Test
    func restoreIsWholeFileAndDoesNotDependOnTheConnectedDisplays() async throws {
        let fixture = await makeFixture()
        let snapshot = try await fixture.action.capture()
        let applied = try await fixture.action.apply()
        await fixture.workspace.connect([])

        #expect(try await fixture.action.restore(snapshot, expecting: applied) == .restored)
        #expect(await fixture.files.contents(of: Self.locations.storeURL) == snapshot.storeData)
    }
}
