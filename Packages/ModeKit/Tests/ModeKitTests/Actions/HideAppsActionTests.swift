import ModeKit
import Testing

struct HideAppsActionTests {
    private typealias Snapshot = HideAppsAction.Snapshot
    private typealias Applied = HideAppsAction.AppliedState

    private let mail: BundleIdentifier
    private let notes: BundleIdentifier
    private let safari: BundleIdentifier
    private let terminal: BundleIdentifier
    private let presenter: BundleIdentifier
    private let music: BundleIdentifier

    init() throws {
        mail = try BundleIdentifier("com.example.mail")
        notes = try BundleIdentifier("com.example.notes")
        safari = try BundleIdentifier("com.example.safari")
        terminal = try BundleIdentifier("com.example.terminal")
        presenter = try BundleIdentifier("com.example.presenter")
        music = try BundleIdentifier("com.example.music")
    }

    /// Notes and Mail visible, Safari already hidden, Terminal frontmost, this application, Music excluded.
    private var desktop: [RunningApplication] {
        [
            .fixture(notes),
            .fixture(safari, .hidden),
            .fixture(terminal, role: .frontmost),
            .fixture(presenter, role: .thisApplication),
            .fixture(mail),
            .fixture(music),
        ]
    }

    private func makeAction(_ applications: [RunningApplication]) -> (HideAppsAction, FakeWorkspaceAdapter) {
        let workspace = FakeWorkspaceAdapter(applications)
        return (HideAppsAction(exclusions: [music], workspace: workspace), workspace)
    }

    // Per-action scenario: capture reads current state
    @Test
    func captureListsTheVisibleCandidatesSortedAndChangesNothing() async throws {
        let (action, workspace) = makeAction(desktop)

        #expect(try await action.capture() == Snapshot(candidates: [mail, notes]))
        #expect(await workspace.calls == [.list])
        #expect(await workspace.applications == desktop)
    }

    // Per-action scenario: apply sets the expected state
    @Test
    func applyHidesEachCandidateInOrderAndNothingElse() async throws {
        let (action, workspace) = makeAction(desktop)

        #expect(try await action.apply() == Applied(hidden: [mail, notes]))
        #expect(await workspace.calls == [.list, .hide(mail), .hide(notes)])
        #expect(
            await workspace.applications
                == desktop.map { [mail, notes].contains($0.bundleIdentifier) ? $0.with(.hidden) : $0 })
    }

    @Test
    func theFrontmostApplicationAndThisApplicationAreNeverHidden() async throws {
        let (action, workspace) = makeAction([
            .fixture(terminal, role: .frontmost), .fixture(presenter, role: .thisApplication),
        ])

        #expect(try await action.capture() == Snapshot(candidates: []))
        #expect(try await action.apply() == Applied(hidden: []))
        #expect(await workspace.calls == [.list, .list])
    }

    // Per-action scenario: state already equal to the target
    @Test
    func noCandidatesWhenEveryRunningApplicationIsHiddenOrExcluded() async throws {
        let (action, workspace) = makeAction([.fixture(safari, .hidden), .fixture(music)])

        #expect(try await action.capture() == Snapshot(candidates: []))
        #expect(try await action.apply() == Applied(hidden: []))
        #expect(await workspace.calls == [.list, .list])
    }

    @Test
    func severalInstancesOfOneApplicationAreOneCandidate() async throws {
        let (action, _) = makeAction([.fixture(notes), .fixture(notes)])

        #expect(try await action.capture() == Snapshot(candidates: [notes]))
    }

    // Per-action scenario: the system call fails
    @Test
    func anApplicationThatRefusesToHideIsSkippedWithoutError() async throws {
        let (action, workspace) = makeAction(desktop)
        await workspace.refuse(.hide, of: mail)

        #expect(try await action.apply() == Applied(hidden: [notes]))
        #expect(await workspace.calls == [.list, .hide(mail), .hide(notes)])
    }

    @Test
    func anApplicationThatQuitBetweenCaptureAndApplyIsNotHidden() async throws {
        let (action, workspace) = makeAction(desktop)
        _ = try await action.capture()
        await workspace.quit(mail)

        #expect(try await action.apply() == Applied(hidden: [notes]))
        #expect(await workspace.calls == [.list, .list, .hide(notes)])
    }

    @Test
    func anApplicationThatQuitJustBeforeItsHideIsSkippedWithoutError() async throws {
        let (action, workspace) = makeAction(desktop)
        await workspace.quitBefore(.hide, of: mail)

        #expect(try await action.apply() == Applied(hidden: [notes]))
    }

    @Test
    func restoreUnhidesWhatApplyHidAndLeavesTheAlreadyHiddenApplicationHidden() async throws {
        let (action, workspace) = makeAction(desktop)
        let snapshot = try await action.capture()
        let applied = try await action.apply()

        #expect(try await action.restore(snapshot, expecting: applied) == .restored)
        #expect(await workspace.applications == desktop)
    }
}
