import Foundation

/// The real ``FileStore``, on the local file system. Foundation only, so it lives in ModeKit (ADR-029).
///
/// A write goes to a temporary file in the target's directory, is flushed to permanent storage with
/// `fcntl(F_FULLFSYNC)`, and replaces the target with `rename(2)`, which is atomic within one volume. Per fsync(2),
/// plain `fsync` hands data to the drive, which may hold it in its own buffers for some time. The parent directory
/// is then flushed the same way, so the rename itself survives a power loss (ADR-033). A failure before the rename
/// leaves the previous file intact and removes the temporary file.
///
/// Cost: the file flush took 2.8 to 5.9 ms (median 3.8 ms, 20 runs) on the M0 test Mac's internal SSD, where plain
/// `fsync` returned in under 0.01 ms; slower drives take longer. The session controller writes `session.json` once
/// at the start of an activation and once per applied action.
///
/// Threading: stateless and `Sendable`. The calls block the calling thread for the duration of the I/O, which
/// is acceptable for the small files ModeKit writes.
public struct FileManagerFileStore: FileStore {
    private static let temporaryFilePrefix = "."
    private static let temporaryFileSuffix = ".tmp"

    /// Creates a file store on the local file system.
    public init() {}

    public func read(_ url: URL) async throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func write(_ data: Data, to url: URL) async throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = Self.temporaryFilePrefix + url.lastPathComponent + "." + UUID().uuidString
        let temporaryURL = directory.appending(path: fileName + Self.temporaryFileSuffix)
        do {
            try writeAndSynchronize(data, to: temporaryURL)
            try moveReplacing(temporaryURL, to: url)
        } catch {
            removeTemporaryFile(temporaryURL)
            throw error
        }
        flushDirectory(directory)
    }

    public func remove(_ url: URL) async throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    private func writeAndSynchronize(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: url)
        let synchronization = Result { try Self.flushToStorage(handle.fileDescriptor) }
        try handle.close()
        try synchronization.get()
    }

    /// Flushes through the drive's write cache with `F_FULLFSYNC`; falls back to `fsync` only when the file system
    /// reports `F_FULLFSYNC` as unsupported.
    private static func flushToStorage(_ descriptor: Int32) throws {
        guard fcntl(descriptor, F_FULLFSYNC) != 0 else {
            return
        }
        let fullSyncError = errno
        guard fullSyncError == ENOTSUP || fullSyncError == ENOTTY else {
            throw POSIXError(POSIXErrorCode(rawValue: fullSyncError) ?? .EIO)
        }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func flushDirectory(_ directory: URL) {
        // Best effort, after a completed rename: the new file is in place and the write has succeeded. If the
        // directory entry cannot be flushed, a power loss now may bring back the previous file, which is still
        // complete and valid; reporting a failure here would wrongly tell the caller the new content was not written.
        let descriptor = open(directory.path(percentEncoded: false), O_RDONLY)
        guard descriptor >= 0 else {
            return
        }
        defer { close(descriptor) }
        try? Self.flushToStorage(descriptor)
    }

    private func moveReplacing(_ source: URL, to destination: URL) throws {
        guard rename(source.path(percentEncoded: false), destination.path(percentEncoded: false)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func removeTemporaryFile(_ url: URL) {
        // Cleanup after a failed write. The write error is what the caller needs; when the temporary file was
        // never created there is nothing to remove, so a failed removal does not replace that error.
        try? FileManager.default.removeItem(at: url)
    }
}
