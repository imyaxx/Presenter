/// The ``ActionFactory`` the app uses: builds the concrete actions over the system ports.
///
/// Supports the desktop icons, Dock, menu bar and hide apps steps; the wallpaper step arrives with its action and
/// throws ``ActionError/unsupported(_:)`` until then. Threading: a value type holding its ports.
public struct StandardActionFactory: ActionFactory {
    private let ports: ActionPorts
    private let wallpaperLocations: WallpaperLocations

    /// Creates the factory over the ports the actions need and the wallpaper locations the composition root resolves.
    public init(ports: ActionPorts, wallpaperLocations: WallpaperLocations) {
        self.ports = ports
        self.wallpaperLocations = wallpaperLocations
    }

    /// - Throws: ``ActionError/unsupported(_:)`` for a step without an action yet.
    public func makeAction(for step: ProfileStep) throws -> any ModeAction {
        switch step {
        case .hideDesktopIcons:
            desktopIconsAction
        case .hideDock:
            dockAction
        case .hideMenuBar:
            menuBarAction
        case .hideApps(let exclusions):
            HideAppsAction(exclusions: exclusions, workspace: ports.workspace)
        case .wallpaper:
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
        case .menuBar:
            menuBarAction
        case .hideApps:
            HideAppsRestorer(workspace: ports.workspace)
        case .wallpaper:
            throw ActionError.unsupported(identifier)
        }
    }

    private var desktopIconsAction: DesktopIconsAction {
        DesktopIconsAction(defaults: ports.defaults, processRunner: ports.processRunner)
    }

    private var dockAction: DockAction {
        DockAction(defaults: ports.defaults, appleScriptRunner: ports.appleScriptRunner)
    }

    private var menuBarAction: MenuBarAction {
        MenuBarAction(defaults: ports.defaults, notifier: ports.notifier)
    }
}
