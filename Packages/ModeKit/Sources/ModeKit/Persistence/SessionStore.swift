import Foundation

/// Reads, writes and clears the active session in `session.json` inside an injected directory.
///
/// File policy (docs/12-data-formats.md): a newer `schemaVersion` is refused and never modified. A file that cannot
/// be read is never overwritten, because it may describe system changes that were never reverted; the caller
/// resolves it explicitly with ``clearSession()``.
///
/// Threading: an actor whose file operations run strictly one after another.
public actor SessionStore {
    private let file: VersionedJSONFile<SessionFile>
    private let serializer = TaskSerializer()

    /// Creates a store for `session.json` in `directory`.
    public init(fileStore: any FileStore, directory: URL) {
        file = VersionedJSONFile(fileStore: fileStore, directory: directory, undecodableFilePolicy: .refuseWrite)
    }

    /// Returns the stored session, or nil when no session file exists.
    ///
    /// - Throws: ``StoreError/unsupportedSchemaVersion(found:supported:)``, ``StoreError/corrupted(fileName:reason:)``
    ///   or ``StoreError/ioFailure(fileName:reason:)``.
    public func loadSession() async throws -> SessionRecord? {
        try await serializer.run { [file] in
            try await file.read()?.session
        }
    }

    /// Replaces the session file with `session`, atomically.
    ///
    /// - Throws: ``StoreError/unsupportedSchemaVersion(found:supported:)`` or
    ///   ``StoreError/corrupted(fileName:reason:)`` when the existing file is newer or unreadable, which leaves it
    ///   untouched,
    ///   ``StoreError/ioFailure(fileName:reason:)`` or ``StoreError/encodingFailed(fileName:reason:)``.
    public func saveSession(_ session: SessionRecord) async throws {
        let contents = SessionFile(schemaVersion: SchemaVersion.current, session: session)
        try await serializer.run { [file] in
            try await file.write(contents)
        }
    }

    /// Removes the session file whatever it contains; succeeds when there is none.
    ///
    /// - Throws: ``StoreError/ioFailure(fileName:reason:)``.
    public func clearSession() async throws {
        try await serializer.run { [file] in
            try await file.remove()
        }
    }
}
