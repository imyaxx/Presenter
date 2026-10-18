import Foundation
import ModeKit

/// A ``FileStore`` fake that keeps files in memory, records every call, and fails the next call on request.
actor InMemoryFileStore: FileStore {
    enum Operation: Equatable {
        case read(String)
        case write(String)
        case remove(String)
    }

    struct InjectedFailure: Error, Equatable {}

    private(set) var files: [URL: Data] = [:]
    private(set) var operations: [Operation] = []
    private var failsNextRead = false
    private var failsNextWrite = false
    private var failsNextRemove = false

    func read(_ url: URL) async throws -> Data? {
        operations.append(.read(url.lastPathComponent))
        // A suspension point inside every call, so callers that are not serialized can interleave.
        await Task.yield()
        if failsNextRead {
            failsNextRead = false
            throw InjectedFailure()
        }
        return files[url]
    }

    func write(_ data: Data, to url: URL) async throws {
        operations.append(.write(url.lastPathComponent))
        await Task.yield()
        if failsNextWrite {
            failsNextWrite = false
            throw InjectedFailure()
        }
        files[url] = data
    }

    func remove(_ url: URL) async throws {
        operations.append(.remove(url.lastPathComponent))
        await Task.yield()
        if failsNextRemove {
            failsNextRemove = false
            throw InjectedFailure()
        }
        files[url] = nil
    }

    func failNextRead() { failsNextRead = true }
    func failNextWrite() { failsNextWrite = true }
    func failNextRemove() { failsNextRemove = true }

    func place(_ data: Data, at url: URL) { files[url] = data }
    func contents(of url: URL) -> Data? { files[url] }
    func clearOperations() { operations = [] }
}
