import ModeKit
import Testing

struct HideAppsRestorerTests {
    private typealias Snapshot = HideAppsRestorer.Snapshot
    private typealias Applied = HideAppsRestorer.AppliedState

    private let mail: BundleIdentifier
    private let notes: BundleIdentifier
    private let safari: BundleIdentifier
    private let preview: BundleIdentifier

    init() throws {
        mail = try BundleIdentifier("com.example.mail")
        notes = try BundleIdentifier("com.example.notes")
        safari = try BundleIdentifier("com.example.safari")
        preview = try BundleIdentifier("com.example.preview")
    }

    private var snapshot: Snapshot {
        Snapshot(candidates: [mail, notes])
    }

    private var applied: Applied {
        Applied(hidden: [mail, notes])
    }

    /// The world during a session: Mail and Notes hidden by the action, Safari hidden before activation.
    private func makeRestorer() -> (HideAppsRestorer, FakeWorkspaceAdapter) {
        let workspace = FakeWorkspaceAdapter([
            .fixture(mail, .hidden), .fixture(notes, .hidden), .fixture(safari, .hidden),
        ])
        return (HideAppsRestorer(workspace: workspace), workspace)
    }

    // Per-action scenario: restore returns to the captured state
    @Test
    func restoreUnhidesEachHiddenApplicationInOrder() async throws {
        let (restorer, workspace) = makeRestorer()

        #expect(try await restorer.restore(snapshot, expecting: applied) == .restored)
        #expect(await workspace.calls == [.list, .unhide(mail), .unhide(notes)])
        #expect(await workspace.applications == [.fixture(mail), .fixture(notes), .fixture(safari, .hidden)])
    }

    @Test
    func anApplicationThatQuitDuringTheSessionIsNotRelaunched() async throws {
        let (restorer, workspace) = makeRestorer()
        await workspace.quit(mail)

        #expect(try await restorer.restore(snapshot, expecting: applied) == .restored)
        #expect(await workspace.calls == [.list, .unhide(notes)])
        #expect(await workspace.applications == [.fixture(notes), .fixture(safari, .hidden)])
    }

    @Test
    func anApplicationThatQuitJustBeforeItsUnhideIsNotAnError() async throws {
        let (restorer, workspace) = makeRestorer()
        await workspace.quitBefore(.unhide, of: mail)

        #expect(try await restorer.restore(snapshot, expecting: applied) == .restored)
        #expect(await workspace.applications == [.fixture(notes), .fixture(safari, .hidden)])
    }

    @Test
    func anApplicationTheUserUnhidIsLeftAloneAndTheOthersAreUnhidden() async throws {
        let (restorer, workspace) = makeRestorer()
        await workspace.userUnhides(mail)

        #expect(try await restorer.restore(snapshot, expecting: applied) == .restored)
        #expect(await workspace.calls == [.list, .unhide(notes)])
    }

    // Per-action scenario: restore skips when changed
    @Test
    func restoreIsSkippedWhenTheUserUnhidEveryApplication() async throws {
        let (restorer, workspace) = makeRestorer()
        await workspace.userUnhides(mail)
        await workspace.userUnhides(notes)

        #expect(try await restorer.restore(snapshot, expecting: applied) == .skippedBecauseChangedByUser)
        #expect(await workspace.calls == [.list])
    }

    @Test
    func applicationsTheUserSwitchedToCountAsUnhiddenByTheUser() async throws {
        let (restorer, workspace) = makeRestorer()
        await workspace.activate(notes)
        await workspace.activate(mail)

        #expect(try await restorer.restore(snapshot, expecting: applied) == .skippedBecauseChangedByUser)
        #expect(await workspace.calls == [.list])
        #expect(
            await workspace.applications == [
                .fixture(mail, role: .frontmost), .fixture(notes), .fixture(safari, .hidden),
            ])
    }

    @Test
    func applicationsLaunchedDuringTheSessionAreUntouched() async throws {
        let (restorer, workspace) = makeRestorer()
        await workspace.launch(.fixture(preview, .hidden))

        #expect(try await restorer.restore(snapshot, expecting: applied) == .restored)
        #expect(await workspace.calls == [.list, .unhide(mail), .unhide(notes)])
        #expect(await workspace.applications.last == .fixture(preview, .hidden))
    }

    @Test
    func restoreWithoutAppliedStateUnhidesTheSnapshotCandidates() async throws {
        let workspace = FakeWorkspaceAdapter([.fixture(mail, .hidden), .fixture(notes)])
        let restorer = HideAppsRestorer(workspace: workspace)

        #expect(try await restorer.restore(snapshot, expecting: nil) == .restored)
        #expect(await workspace.calls == [.list, .unhide(mail)])
        #expect(await workspace.applications == [.fixture(mail), .fixture(notes)])
    }

    // Per-action scenario: state already equal to the target
    @Test
    func restoreWithNothingHiddenDoesNothing() async throws {
        let (restorer, workspace) = makeRestorer()

        #expect(try await restorer.restore(snapshot, expecting: Applied(hidden: [])) == .restored)
        #expect(await workspace.calls.isEmpty)
    }

    // Per-action scenario: the system call fails
    @Test
    func aRefusedUnhideIsThrownAfterTheOthersAreUnhidden() async {
        let (restorer, workspace) = makeRestorer()
        await workspace.refuse(.unhide, of: mail)

        await #expect(throws: HideAppsActionError.couldNotUnhide([mail])) {
            try await restorer.restore(snapshot, expecting: applied)
        }
        #expect(await workspace.calls == [.list, .unhide(mail), .unhide(notes)])
        #expect(
            await workspace.applications == [.fixture(mail, .hidden), .fixture(notes), .fixture(safari, .hidden)])
    }

    @Test
    func couldNotUnhideNamesTheApplications() {
        let error = HideAppsActionError.couldNotUnhide([mail, notes])

        #expect(error.description == "Applications refused to unhide: com.example.mail, com.example.notes")
    }
}
