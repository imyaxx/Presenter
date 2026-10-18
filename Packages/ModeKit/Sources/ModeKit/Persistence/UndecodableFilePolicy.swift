/// What a write does when the existing file cannot be read (``StoreError/corrupted(fileName:reason:)``).
enum UndecodableFilePolicy: Sendable {
    /// Keep the unreadable file byte for byte as `<file name>.corrupt` (replacing an older copy), then overwrite.
    case preserveCopyThenOverwrite
    /// Refuse the write. Used for a session file nobody understands, because it may describe system changes
    /// that were never reverted; the caller resolves it explicitly.
    case refuseWrite
}
