import Foundation
import ModeKit
import Testing

struct StandardActionFactoryTests {
    private let factory = StandardActionFactory(
        ports: ActionPorts(
            defaults: FakeDefaultsStore(),
            processRunner: FakeProcessRunner(),
            appleScriptRunner: FakeAppleScriptRunner(),
            workspace: FakeWorkspaceAdapter(),
            notifier: FakeDistributedNotifier(),
            fileStore: InMemoryFileStore(),
            clock: FakeClock(sleeping: .immediate),
            imageRenderer: FakeSolidColorImageRenderer(),
            storeInspector: FakeWallpaperStoreInspector(),
        ),
        wallpaperLocations: StandardActionsHarness.wallpaperLocations,
    )

    @Test(arguments: [
        (ProfileStep.hideDesktopIcons, ActionIdentifier.desktopIcons),
        (.hideDock, .dock),
        (.hideMenuBar, .menuBar),
        (.hideApps(exclusions: []), .hideApps),
        (.wallpaper(.solidColor(SolidColor(red: 0, green: 0, blue: 0)), displays: .allDisplays), .wallpaper),
    ])
    func buildsActionsAndRestorersForEveryStep(step: ProfileStep, identifier: ActionIdentifier) throws {
        #expect(try factory.makeAction(for: step).identifier == identifier)
        #expect(try factory.makeRestorer(for: identifier).identifier == identifier)
    }

    @Test
    func everyIdentifierHasARestorer() throws {
        for identifier in ActionIdentifier.allCases {
            #expect(try factory.makeRestorer(for: identifier).identifier == identifier)
        }
    }

    @Test
    func theRestorersNeedNoProfile() throws {
        #expect(try factory.makeRestorer(for: .hideApps) is HideAppsRestorer)
        #expect(try factory.makeRestorer(for: .wallpaper) is WallpaperRestorer)
    }
}
