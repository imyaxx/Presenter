import Foundation

/// The one implementation of the file policy shared by ``ProfileStore`` and ``SessionStore``.
///
/// Read: the `schemaVersion` header is decoded first. A newer version throws
/// ``StoreError/unsupportedSchemaVersion(found:supported:)`` and the file is never touched. Undecodable or invalid
/// content throws ``StoreError/corrupted(fileName:reason:)``.
/// Write: the existing file is read with the same rules first. A newer version refuses the write; an unreadable
/// file is handled by the ``UndecodableFilePolicy``.
struct VersionedJSONFile<Envelope: VersionedFileEnvelope>: Sendable {
    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    private static var corruptCopySuffix: String { ".corrupt" }

    private let fileStore: any FileStore
    private let url: URL
    private let undecodableFilePolicy: UndecodableFilePolicy

    init(fileStore: any FileStore, directory: URL, undecodableFilePolicy: UndecodableFilePolicy) {
        self.fileStore = fileStore
        self.url = directory.appending(path: Envelope.fileName)
        self.undecodableFilePolicy = undecodableFilePolicy
    }

    /// Returns the validated envelope, or nil when the file does not exist.
    func read() async throws(StoreError) -> Envelope? {
        guard let data = try await readData() else {
            return nil
        }
        return try decode(data)
    }

    /// Writes the envelope after applying the policy to any existing file.
    func write(_ envelope: Envelope) async throws(StoreError) {
        if let existing = try await readData() {
            try await resolveExistingFile(existing)
        }
        try await writeData(try encode(envelope), to: url)
    }

    /// Removes the file regardless of its content.
    func remove() async throws(StoreError) {
        do {
            try await fileStore.remove(url)
        } catch {
            throw .ioFailure(fileName: Envelope.fileName, reason: Self.describe(error, operation: "remove"))
        }
    }

    private func resolveExistingFile(_ data: Data) async throws(StoreError) {
        do {
            _ = try decode(data)
        } catch .corrupted(let fileName, let reason) {
            switch undecodableFilePolicy {
            case .preserveCopyThenOverwrite:
                let copyURL = url.deletingLastPathComponent().appending(path: fileName + Self.corruptCopySuffix)
                try await writeData(data, to: copyURL)
            case .refuseWrite:
                throw .corrupted(fileName: fileName, reason: reason)
            }
        }
    }

    private func decode(_ data: Data) throws(StoreError) -> Envelope {
        let decoder = PersistenceCoding.makeDecoder()
        let header: SchemaHeader
        do {
            header = try decoder.decode(SchemaHeader.self, from: data)
        } catch {
            throw corrupted(data.isEmpty ? "file is empty" : Self.describe(error))
        }
        guard header.schemaVersion <= SchemaVersion.current else {
            throw .unsupportedSchemaVersion(found: header.schemaVersion, supported: SchemaVersion.current)
        }
        // No older format exists: version 1 is the first. A value below it was never written by any build, so the
        // file is treated as corrupt rather than old.
        guard header.schemaVersion == SchemaVersion.current else {
            throw corrupted("schemaVersion \(header.schemaVersion) is not a valid version")
        }
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw corrupted(Self.describe(error))
        }
        return try envelope.validated()
    }

    private func encode(_ envelope: Envelope) throws(StoreError) -> Data {
        do {
            return try PersistenceCoding.makeEncoder().encode(envelope)
        } catch {
            throw .encodingFailed(fileName: Envelope.fileName, reason: String(describing: error))
        }
    }

    private func readData() async throws(StoreError) -> Data? {
        do {
            return try await fileStore.read(url)
        } catch {
            throw .ioFailure(fileName: Envelope.fileName, reason: Self.describe(error, operation: "read"))
        }
    }

    private func writeData(_ data: Data, to destination: URL) async throws(StoreError) {
        do {
            try await fileStore.write(data, to: destination)
        } catch {
            throw .ioFailure(
                fileName: destination.lastPathComponent, reason: Self.describe(error, operation: "write"), )
        }
    }

    private func corrupted(_ reason: String) -> StoreError {
        .corrupted(fileName: Envelope.fileName, reason: reason)
    }

    private static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return String(describing: type(of: error))
        }
        switch decodingError {
        case .dataCorrupted(let context), .keyNotFound(_, let context), .typeMismatch(_, let context),
            .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return "undecodable content"
        }
    }

    /// Domain and code only: a Foundation error's description can contain a full path.
    private static func describe(_ error: any Error, operation: String) -> String {
        let nsError = error as NSError
        return "\(operation) failed (\(nsError.domain) \(nsError.code))"
    }
}
