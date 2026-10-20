import AppKit

/// Shows the app's support directory, which holds `profiles.json`, in Finder (ADR-043).
///
/// Creates the directory first when it is missing. Threading: a value type; the Finder call hops to the main actor.
struct NSWorkspaceProfilesFolderRevealer: Sendable {
    let directory: URL

    /// Creates the directory and its parents when missing. Succeeds when it exists.
    ///
    /// - Throws: The error of `FileManager.createDirectory(at:withIntermediateDirectories:attributes:)`.
    func createDirectoryIfMissing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// - Throws: ``createDirectoryIfMissing()``'s error, or ``ProfilesFolderError/finderRefused`` when Finder does
    ///   not open the folder.
    func reveal() async throws {
        try createDirectoryIfMissing()
        let opened = await MainActor.run { NSWorkspace.shared.open(directory) }
        guard opened else {
            throw ProfilesFolderError.finderRefused
        }
    }
}

/// A failure to show the profiles folder.
enum ProfilesFolderError: Error, Equatable, Sendable {
    /// `NSWorkspace.open(_:)` returned false.
    case finderRefused
}
