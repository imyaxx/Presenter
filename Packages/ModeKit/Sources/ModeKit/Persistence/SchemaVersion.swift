/// Version of the on-disk JSON schema shared by every file ModeKit persists.
///
/// Each persisted file records the version it was written with. When a file is read,
/// its recorded version is compared against ``current``: an older version is migrated,
/// and a newer (unknown) version is refused without overwriting the file.
///
/// Thread safety: a compile-time constant, safe to read from any context.
public enum SchemaVersion {
    /// The schema version this build of ModeKit writes and fully understands.
    public static let current = 1
}
