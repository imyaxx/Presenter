import Foundation
import ModeKit
import Testing

struct SessionStoreTests {
    private let directory = URL(filePath: "/Store")
    private let fileStore = InMemoryFileStore()
    private var fileURL: URL { directory.appending(path: "session.json") }

    private func makeStore() -> SessionStore {
        SessionStore(fileStore: fileStore, directory: directory)
    }

    @Test
    func loadReturnsNilWhenNoSessionExists() async throws {
        #expect(try await makeStore().loadSession() == nil)
    }

    @Test
    func saveThenLoadReturnsSameRecord() async throws {
        let store = makeStore()
        let record = SessionRecordBuilder(
            profileName: "Запись 🎥",
            actions: [
                ActionRecord(identifier: .desktopIcons, snapshotData: Data([0, 1]), appliedData: Data([2])),
                ActionRecord(identifier: .wallpaper, snapshotData: Data(), appliedData: nil),
            ],
        )
        .build()

        try await store.saveSession(record)

        #expect(try await store.loadSession() == record)
    }

    @Test
    func largeSnapshotRoundTrips() async throws {
        let store = makeStore()
        let snapshot = Data((0..<512_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let record = SessionRecordBuilder(
            actions: [ActionRecord(identifier: .wallpaper, snapshotData: snapshot, appliedData: snapshot)]
        )
        .build()

        try await store.saveSession(record)

        #expect(try await store.loadSession() == record)
    }

    @Test
    func fileHasVersionHeaderISODateBase64DataAndOmitsNilAppliedData() async throws {
        try await makeStore().saveSession(SessionRecordBuilder().build())

        let data = try #require(await fileStore.contents(of: fileURL))
        let json = try #require(String(bytes: data, encoding: .utf8))
        #expect(json.contains(#""schemaVersion" : 1"#))
        #expect(json.contains(#""startedAt" : "2026-10-17T12:00:00Z""#))
        #expect(json.contains(#""snapshotData" : "eyJhdXRvaGlkZSI6dHJ1ZX0=""#))
        #expect(!json.contains("appliedData"))
    }

    @Test
    func clearSessionRemovesFileAndSucceedsWhenAbsent() async throws {
        let store = makeStore()
        try await store.saveSession(SessionRecordBuilder().build())

        try await store.clearSession()
        try await store.clearSession()

        #expect(try await store.loadSession() == nil)
    }

    @Test
    func failedWriteReportsIOFailureAndKeepsPreviousSession() async throws {
        let store = makeStore()
        let previous = SessionRecordBuilder().build()
        try await store.saveSession(previous)
        await fileStore.failNextWrite()

        await #expect {
            try await store.saveSession(SessionRecordBuilder(profileName: "Other").build())
        } throws: { error in
            guard case .ioFailure(let fileName, _) = error as? StoreError else {
                return false
            }
            return fileName == "session.json"
        }

        #expect(try await store.loadSession() == previous)
    }

    @Test
    func failedRemoveReportsIOFailure() async {
        await fileStore.failNextRemove()

        await #expect {
            try await makeStore().clearSession()
        } throws: { error in
            guard case .ioFailure(let fileName, _) = error as? StoreError else {
                return false
            }
            return fileName == "session.json"
        }
    }

    @Test
    func concurrentSaveAndClearRunOneAfterAnother() async throws {
        let store = makeStore()

        async let save: Void = store.saveSession(SessionRecordBuilder().build())
        async let clear: Void = store.clearSession()
        _ = try await (save, clear)

        let operations = await fileStore.operations
        let saveOperations: [InMemoryFileStore.Operation] = [.read("session.json"), .write("session.json")]
        let clearOperations: [InMemoryFileStore.Operation] = [.remove("session.json")]
        #expect(operations == saveOperations + clearOperations || operations == clearOperations + saveOperations)
    }
}
