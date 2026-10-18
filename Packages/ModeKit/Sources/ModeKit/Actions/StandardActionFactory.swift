/// The ``ActionFactory`` the app uses: builds the concrete actions over the system ports.
///
/// Supports all five steps and identifiers. ``ActionError/unsupported(_:)`` stays in the contract for anything the
/// enums might gain. Threading: a value type holding its ports.
public struct StandardActionFactory: ActionFactory {
    private let ports: ActionPorts
    private let wallpaperLocations: WallpaperLocations

    /// Creates the factory over the ports the actions need and the wallpaper locations the composition root resolves.
    public init(ports: ActionPorts, wallpaperLocations: WallpaperLocations) {
        self.ports = ports
        self.wallpaperLocations = wallpaperLocations
    }

    /// Builds the action for `step`; never throws for the current steps.
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
        case .wallpaper(let choice, let displays):
            WallpaperAction(choice: choice, displays: displays, ports: ports, locations: wallpaperLocations)
        }
    }

    /// Builds the restorer for `identifier`; never throws for the current identifiers.
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
            WallpaperRestorer(
                fileStore: ports.fileStore,
                processRunner: ports.processRunner,
                storeInspector: ports.storeInspector,
                storeURL: wallpaperLocations.storeURL,
            )
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
