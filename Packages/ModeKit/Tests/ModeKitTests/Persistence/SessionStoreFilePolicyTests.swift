import Foundation
import ModeKit
import Testing

struct SessionStoreFilePolicyTests {
    private let directory = URL(filePath: "/Store")
    private let fileStore = InMemoryFileStore()
    private var fileURL: URL { directory.appending(path: "session.json") }

    static let corruptedContents: [String] = [
        "",
        #"{"schemaVersion":1,"session":{"sessionID":"#,
        #"{"schemaVersion":1}"#,
        #"{"schemaVersion":1,"session":{"sessionID":"A0000000-0000-0000-0000-000000000001"}}"#,
        #"{"schemaVersion":-3,"session":{}}"#,
    ]

    private func makeStore() -> SessionStore {
        SessionStore(fileStore: fileStore, directory: directory)
    }

    @Test
    func newerSchemaVersionIsRefusedAndNeverModifiedExceptByClear() async throws {
        let newer = Data(#"{"schemaVersion":7,"session":{"future":true}}"#.utf8)
        await fileStore.place(newer, at: fileURL)
        let store = makeStore()
        let refusal = StoreError.unsupportedSchemaVersion(found: 7, supported: SchemaVersion.current)

        await #expect(throws: refusal) { try await store.loadSession() }
        await #expect(throws: refusal) { try await store.saveSession(SessionRecordBuilder().build()) }
        #expect(await fileStore.contents(of: fileURL) == newer)
        #expect(await !fileStore.operations.contains(.write("session.json")))

        try await store.clearSession()

        #expect(await fileStore.contents(of: fileURL) == nil)
    }

    @Test(arguments: corruptedContents)
    func unreadableSessionIsReportedAsCorruptedOnLoad(contents: String) async {
        await fileStore.place(Data(contents.utf8), at: fileURL)

        await #expect {
            try await makeStore().loadSession()
        } throws: { error in
            guard case .corrupted(let fileName, _) = error as? StoreError else {
                return false
            }
            return fileName == "session.json"
        }
    }

    @Test(arguments: corruptedContents)
    func unreadableSessionIsNeverOverwrittenAndGetsNoCopy(contents: String) async {
        let unreadable = Data(contents.utf8)
        await fileStore.place(unreadable, at: fileURL)

        await #expect(throws: StoreError.self) {
            try await makeStore().saveSession(SessionRecordBuilder().build())
        }

        #expect(await fileStore.contents(of: fileURL) == unreadable)
        #expect(await fileStore.files.count == 1)
    }

    @Test
    func clearResolvesUnreadableSessionSoTheNextSaveSucceeds() async throws {
        await fileStore.place(Data("{".utf8), at: fileURL)
        let store = makeStore()
        let record = SessionRecordBuilder().build()

        try await store.clearSession()
        try await store.saveSession(record)

        #expect(try await store.loadSession() == record)
    }
}
