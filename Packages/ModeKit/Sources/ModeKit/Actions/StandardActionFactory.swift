/// The ``ActionFactory`` the app uses: builds the concrete actions over the system ports.
///
/// Supports the desktop icons and Dock steps; the other steps arrive with their actions and throw
/// ``ActionError/unsupported(_:)`` until then. Threading: a value type holding its ports.
public struct StandardActionFactory: ActionFactory {
    private let defaults: any DefaultsStore
    private let processRunner: any ProcessRunner
    private let appleScriptRunner: any AppleScriptRunner

    /// Creates the factory over the ports the actions need.
    public init(
        defaults: any DefaultsStore,
        processRunner: any ProcessRunner,
        appleScriptRunner: any AppleScriptRunner,
    ) {
        self.defaults = defaults
        self.processRunner = processRunner
        self.appleScriptRunner = appleScriptRunner
    }

    /// - Throws: ``ActionError/unsupported(_:)`` for a step without an action yet.
    public func makeAction(for step: ProfileStep) throws -> any ModeAction {
        switch step {
        case .hideDesktopIcons:
            desktopIconsAction
        case .hideDock:
            dockAction
        case .hideMenuBar, .hideApps, .wallpaper:
            throw ActionError.unsupported(step.actionIdentifier)
        }
    }

    /// - Throws: ``ActionError/unsupported(_:)`` for an identifier without an action yet.
    public func makeRestorer(for identifier: ActionIdentifier) throws -> any ActionRestorer {
        switch identifier {
        case .desktopIcons:
            desktopIconsAction
        case .dock:
            dockAction
        case .menuBar, .hideApps, .wallpaper:
            throw ActionError.unsupported(identifier)
        }
    }

    private var desktopIconsAction: DesktopIconsAction {
        DesktopIconsAction(defaults: defaults, processRunner: processRunner)
    }

    private var dockAction: DockAction {
        DockAction(defaults: defaults, appleScriptRunner: appleScriptRunner)
    }
}
