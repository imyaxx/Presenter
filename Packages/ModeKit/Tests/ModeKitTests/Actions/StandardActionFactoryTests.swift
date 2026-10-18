import ModeKit
import Testing

struct StandardActionFactoryTests {
    private let factory = StandardActionFactory(
        defaults: FakeDefaultsStore(),
        processRunner: FakeProcessRunner(),
        appleScriptRunner: FakeAppleScriptRunner(),
    )

    @Test(arguments: [(ProfileStep.hideDesktopIcons, ActionIdentifier.desktopIcons), (.hideDock, .dock)])
    func buildsActionsForSupportedSteps(step: ProfileStep, identifier: ActionIdentifier) throws {
        #expect(try factory.makeAction(for: step).identifier == identifier)
        #expect(try factory.makeRestorer(for: identifier).identifier == identifier)
    }

    @Test(arguments: [
        ProfileStep.hideMenuBar,
        .hideApps(exclusions: []),
        .wallpaper(.solidColor(SolidColor(red: 0, green: 0, blue: 0)), displays: .allDisplays),
    ])
    func rejectsStepsWithoutAnActionYet(step: ProfileStep) {
        #expect(throws: ActionError.unsupported(step.actionIdentifier)) { try factory.makeAction(for: step) }
        #expect(throws: ActionError.unsupported(step.actionIdentifier)) {
            try factory.makeRestorer(for: step.actionIdentifier)
        }
    }
}
