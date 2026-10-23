import ModeKit

/// Loads the profiles from `profiles.json` (ADR-043). `ProfileStore` conforms in `Application/`.
protocol ProfileLoading: Sendable {
    /// The profiles in file order; empty when there is no file.
    ///
    /// - Throws: A `StoreError` when the file cannot be read, is corrupted or was written by a newer version.
    func loadProfiles() async throws -> [Profile]
}
