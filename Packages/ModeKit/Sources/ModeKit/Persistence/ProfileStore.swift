import Foundation

/// Reads and writes the user's profiles in `profiles.json` inside an injected directory.
///
/// The composition root passes the directory (Application Support for the app); ModeKit never resolves paths.
/// File policy (docs/12-data-formats.md): a newer `schemaVersion` is refused and never modified; a file that
/// cannot be read is copied to `profiles.json.corrupt` before a save overwrites it.
///
/// Threading: an actor whose file operations run strictly one after another, so concurrent saves never interleave.
public actor ProfileStore {
    private let file: VersionedJSONFile<ProfilesFile>
    private let serializer = TaskSerializer()

    /// Creates a store for `profiles.json` in `directory`.
    public init(fileStore: any FileStore, directory: URL) {
        file = VersionedJSONFile(
            fileStore: fileStore,
            directory: directory,
            undecodableFilePolicy: .preserveCopyThenOverwrite,
        )
    }

    /// Returns the stored profiles in file order with trimmed names; an empty array when no file exists.
    ///
    /// - Throws: ``StoreError/unsupportedSchemaVersion(found:supported:)``, ``StoreError/corrupted(fileName:reason:)``
    ///   or ``StoreError/ioFailure(fileName:reason:)``.
    public func loadProfiles() async throws -> [Profile] {
        try await serializer.run { [file] in
            try await file.read()?.profiles ?? []
        }
    }

    /// Validates the profiles and replaces the file with them.
    ///
    /// Nothing is written when validation fails. Names are stored trimmed.
    /// - Throws: ``StoreError/invalidProfile(_:)``, ``StoreError/duplicateProfileID(_:)``,
    ///   ``StoreError/unsupportedSchemaVersion(found:supported:)`` (existing file is newer),
    ///   ``StoreError/ioFailure(fileName:reason:)`` or ``StoreError/encodingFailed(fileName:reason:)``.
    public func saveProfiles(_ profiles: [Profile]) async throws {
        let contents = ProfilesFile(
            schemaVersion: SchemaVersion.current, profiles: try ProfilesFile.validate(profiles), )
        try await serializer.run { [file] in
            try await file.write(contents)
        }
    }
}
