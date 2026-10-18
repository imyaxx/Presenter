import Foundation
import ModeKit
import Testing

/// Integration tests against the real file system, each in its own temporary directory.
final class FileManagerFileStoreTests {
    private let directory: URL
    private let store = FileManagerFileStore()
    private let readOnlyPermissions = 0o555
    private let writablePermissions = 0o755

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ModeKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        // Best-effort cleanup of the test's own temporary directory; a leftover directory fails no assertion.
        try? FileManager.default.removeItem(at: directory)
    }

    @Test
    func readOfMissingFileReturnsNil() async throws {
        #expect(try await store.read(directory.appending(path: "absent.json")) == nil)
    }

    @Test
    func writeThenReadReturnsSameBytes() async throws {
        let url = directory.appending(path: "profiles.json")
        let data = Data("{\"schemaVersion\":1}".utf8)

        try await store.write(data, to: url)

        #expect(try await store.read(url) == data)
    }

    @Test
    func writeReplacesExistingFile() async throws {
        let url = directory.appending(path: "profiles.json")
        try await store.write(Data("old".utf8), to: url)

        try await store.write(Data("new".utf8), to: url)

        #expect(try await store.read(url) == Data("new".utf8))
        #expect(try directoryEntries() == ["profiles.json"])
    }

    @Test
    func writeCreatesMissingParentDirectories() async throws {
        let url = directory.appending(path: "Application Support/dev.example/profiles.json")

        try await store.write(Data("x".utf8), to: url)

        #expect(try await store.read(url) == Data("x".utf8))
    }

    @Test
    func repeatedFlushedWritesInAFreshDirectoryLeaveOnlyTheTarget() async throws {
        let freshDirectory = directory.appending(path: "fresh")
        let url = freshDirectory.appending(path: "session.json")

        for generation in 1...5 {
            try await store.write(Data("generation \(generation)".utf8), to: url)
        }

        #expect(try await store.read(url) == Data("generation 5".utf8))
        let entries = try FileManager.default.contentsOfDirectory(atPath: freshDirectory.path(percentEncoded: false))
        #expect(entries == ["session.json"])
    }

    @Test
    func removeDeletesFileAndSucceedsWhenAbsent() async throws {
        let url = directory.appending(path: "session.json")
        try await store.write(Data("x".utf8), to: url)

        try await store.remove(url)
        try await store.remove(url)

        #expect(try await store.read(url) == nil)
    }

    @Test
    func failedWriteInReadOnlyDirectoryKeepsPreviousFileAndLeavesNoTemporaryFile() async throws {
        let url = directory.appending(path: "profiles.json")
        let previous = Data("previous".utf8)
        try await store.write(previous, to: url)
        try setPermissions(readOnlyPermissions)
        // Restores write access even if an expectation fails, so deinit can delete the directory.
        defer { try? setPermissions(writablePermissions) }

        await #expect(throws: (any Error).self) {
            try await store.write(Data("next".utf8), to: url)
        }

        try setPermissions(writablePermissions)
        #expect(try await store.read(url) == previous)
        #expect(try directoryEntries() == ["profiles.json"])
    }

    @Test
    func failedReplaceRemovesTemporaryFileAndKeepsTarget() async throws {
        let target = directory.appending(path: "occupied")
        try FileManager.default.createDirectory(at: target.appending(path: "child"), withIntermediateDirectories: true)

        await #expect(throws: POSIXError.self) {
            try await store.write(Data("x".utf8), to: target)
        }

        #expect(try directoryEntries() == ["occupied"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path(percentEncoded: false)) == ["child"])
    }

    @Test
    func readOfDirectoryThrowsInsteadOfReturningNil() async {
        await #expect(throws: (any Error).self) {
            try await store.read(directory)
        }
    }

    private func directoryEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }

    private func setPermissions(_ permissions: Int) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: directory.path(percentEncoded: false),
        )
    }
}
