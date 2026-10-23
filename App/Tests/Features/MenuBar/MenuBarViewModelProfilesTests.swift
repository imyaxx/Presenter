import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// The profile list, the profiles folder and the unavailable app.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MenuBarViewModelProfilesTests {
    @Test
    func profilesAreReloadedEachTimeThePopoverOpens() async {
        let harness = MenuBarTestHarness(profiles: [])
        await harness.start()
        #expect(harness.model.profiles.isEmpty)
        await harness.profiles.set(.success([MenuBarFixtures.quick]))

        await harness.model.popoverDidOpen()
        await harness.model.popoverDidOpen()

        #expect(harness.model.profiles == [MenuBarFixtures.quick])
        #expect(await harness.profiles.loadCount == 3)
        harness.stop()
    }

    @Test(arguments: [
        (StoreError.corrupted(fileName: "profiles.json", reason: "x"), ProfilesProblem.corrupted),
        (.unsupportedSchemaVersion(found: 2, supported: 1), .newerVersion),
        (.ioFailure(fileName: "profiles.json", reason: "x"), .unreadable),
    ])
    func aProfilesFileThatCannotBeLoadedIsReportedAndTheListEmptied(
        error: StoreError,
        expected: ProfilesProblem,
    ) async {
        let harness = MenuBarTestHarness()
        await harness.start()
        await harness.profiles.set(.failure(error))

        await harness.model.popoverDidOpen()

        #expect(harness.model.profiles.isEmpty)
        #expect(harness.model.profilesProblem == expected)
        await harness.profiles.set(.success([MenuBarFixtures.quick]))
        await harness.model.popoverDidOpen()
        #expect(harness.model.profilesProblem == nil)
        harness.stop()
    }

    @Test
    func revealingTheProfilesFolderReportsAFailure() async {
        let harness = MenuBarTestHarness()
        await harness.start()

        await harness.model.revealProfilesFolder()
        #expect(harness.model.notice == nil)
        await harness.revealer.fail(with: CocoaError(.fileWriteNoPermission))
        await harness.model.revealProfilesFolder()

        #expect(await harness.revealer.revealCount == 2)
        #expect(harness.model.notice == .profilesFolderUnavailable)
        harness.model.dismissNotice()
        #expect(harness.model.notice == nil)
        harness.stop()
    }

    @Test
    func anUnavailableAppOffersNothingButQuit() async {
        let model = MenuBarViewModel.unavailable()

        await model.recoverAtLaunch()
        await model.popoverDidOpen()
        await model.activate(MenuBarFixtures.quick)
        await model.revealProfilesFolder()

        #expect(model.presentation == .unavailable)
        #expect(model.iconShape == .needsAttention)
        #expect(!model.canActivate && !model.canStop && !model.canRetryRestore && !model.canDiscardSessionFile)
        #expect(model.notice == nil)
    }
}
