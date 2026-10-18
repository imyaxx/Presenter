import Foundation

/// The real ``FileStore``, on the local file system. Foundation only, so it lives in ModeKit (ADR-029).
///
/// A write goes to a temporary file in the target's directory, is flushed to disk with `fsync`, and replaces the
/// target with `rename(2)`, which is atomic within one volume. A failure at any step leaves the previous file
/// intact and removes the temporary file.
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
        let synchronization = Result { try handle.synchronize() }
        try handle.close()
        try synchronization.get()
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
