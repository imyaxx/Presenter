/// The services the menu bar view model works with, built by `AppEnvironment` (ADR-043).
struct MenuBarServices: Sendable {
    let session: any SessionControlling
    let profiles: any ProfileLoading
    let folderRevealer: any ProfilesFolderRevealing
}
