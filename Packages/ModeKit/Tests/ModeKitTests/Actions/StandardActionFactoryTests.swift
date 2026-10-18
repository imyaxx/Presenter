import ModeKit
import Testing

struct StandardActionFactoryTests {
    private let factory = StandardActionFactory(
        defaults: FakeDefaultsStore(),
        processRunner: FakeProcessRunner(),
        appleScriptRunner: FakeAppleScriptRunner(),
        workspace: FakeWorkspaceAdapter(),
        notifier: FakeDistributedNotifier(),
    )

    @Test(arguments: [
        (ProfileStep.hideDesktopIcons, ActionIdentifier.desktopIcons),
        (.hideDock, .dock),
        (.hideMenuBar, .menuBar),
        (.hideApps(exclusions: []), .hideApps),
    ])
    func buildsActionsForSupportedSteps(step: ProfileStep, identifier: ActionIdentifier) throws {
        #expect(try factory.makeAction(for: step).identifier == identifier)
        #expect(try factory.makeRestorer(for: identifier).identifier == identifier)
    }

    @Test
    func theHideAppsRestorerNeedsNoProfile() throws {
        #expect(try factory.makeRestorer(for: .hideApps) is HideAppsRestorer)
    }

    @Test
    func rejectsTheWallpaperStepWithoutAnActionYet() {
        let step = ProfileStep.wallpaper(.solidColor(SolidColor(red: 0, green: 0, blue: 0)), displays: .allDisplays)

        #expect(throws: ActionError.unsupported(.wallpaper)) { try factory.makeAction(for: step) }
        #expect(throws: ActionError.unsupported(.wallpaper)) { try factory.makeRestorer(for: .wallpaper) }
    }
}
