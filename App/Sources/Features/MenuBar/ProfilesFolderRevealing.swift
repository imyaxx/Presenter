/// Shows the folder that holds `profiles.json` in Finder, creating it when it is missing (ADR-043).
protocol ProfilesFolderRevealing: Sendable {
    /// - Throws: An error when the folder cannot be created or shown.
    func revealProfilesFolder() async throws
}
