/// The Finder adapter serves the menu bar's "Show Profiles in Finder" (ADR-043).
extension NSWorkspaceProfilesFolderRevealer: ProfilesFolderRevealing {
    func revealProfilesFolder() async throws {
        try await reveal()
    }
}
