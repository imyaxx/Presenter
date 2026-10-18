import ModeKit

/// An ``ActionFactory`` over a fixed set of fake actions; unknown identifiers are unsupported.
struct FakeActionFactory: ActionFactory {
    let actions: [ActionIdentifier: FakeModeAction]

    func makeAction(for step: ProfileStep) throws -> any ModeAction {
        try action(for: step.actionIdentifier)
    }

    func makeRestorer(for identifier: ActionIdentifier) throws -> any ActionRestorer {
        try action(for: identifier)
    }

    private func action(for identifier: ActionIdentifier) throws(ActionError) -> FakeModeAction {
        guard let action = actions[identifier] else {
            throw .unsupported(identifier)
        }
        return action
    }
}
