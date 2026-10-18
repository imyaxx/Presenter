/// Every port the standard actions use, grouped so ``StandardActionFactory`` takes one value.
///
/// Threading: a value of `Sendable` ports.
public struct ActionPorts: Sendable {
    public let defaults: any DefaultsStore
    public let processRunner: any ProcessRunner
    public let appleScriptRunner: any AppleScriptRunner
    public let workspace: any WorkspaceAdapter
    public let notifier: any DistributedNotifier
    public let fileStore: any FileStore
    /// Paces the wallpaper action's polling of the store.
    public let clock: any SessionClock
    public let imageRenderer: any SolidColorImageRenderer
    public let storeInspector: any WallpaperStoreInspector

    /// Groups the ports.
    public init(
        defaults: any DefaultsStore,
        processRunner: any ProcessRunner,
        appleScriptRunner: any AppleScriptRunner,
        workspace: any WorkspaceAdapter,
        notifier: any DistributedNotifier,
        fileStore: any FileStore,
        clock: any SessionClock,
        imageRenderer: any SolidColorImageRenderer,
        storeInspector: any WallpaperStoreInspector,
    ) {
        self.defaults = defaults
        self.processRunner = processRunner
        self.appleScriptRunner = appleScriptRunner
        self.workspace = workspace
        self.notifier = notifier
        self.fileStore = fileStore
        self.clock = clock
        self.imageRenderer = imageRenderer
        self.storeInspector = storeInspector
    }
}
