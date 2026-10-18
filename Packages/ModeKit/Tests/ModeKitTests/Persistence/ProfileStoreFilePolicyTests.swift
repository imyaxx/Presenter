import Foundation
import ModeKit
import Testing

struct ProfileStoreFilePolicyTests {
    private let directory = URL(filePath: "/Store")
    private let fileStore = InMemoryFileStore()
    private var fileURL: URL { directory.appending(path: "profiles.json") }
    private var corruptCopyURL: URL { directory.appending(path: "profiles.json.corrupt") }

    static let corruptedContents: [String] = [
        "",
        "{",
        #"{"schemaVersion":1,"profiles":[{"id":"6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21","#,
        "[1, 2, 3]",
        #"{"profiles":[]}"#,
        #"{"schemaVersion":"one","profiles":[]}"#,
        #"{"schemaVersion":0,"profiles":[]}"#,
        #"{"schemaVersion":1}"#,
        #"{"schemaVersion":1,"profiles":{}}"#,
        #"{"schemaVersion":1,"profiles":[{"id":"6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21","name":"A","#
            + #""steps":[{"type":"hideNotifications"}]}]}"#,
        #"{"schemaVersion":1,"profiles":[{"id":"6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21","name":"A","#
            + #""steps":[{"type":"hideDock"},{"type":"hideDock"}]}]}"#,
        #"{"schemaVersion":1,"profiles":[{"id":"6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21","name":"A","steps":[]},"#
            + #"{"id":"6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21","name":"B","steps":[]}]}"#,
    ]

    private func makeStore() -> ProfileStore {
        ProfileStore(fileStore: fileStore, directory: directory)
    }

    @Test
    func newerSchemaVersionIsRefusedOnLoadAndSaveAndNeverModified() async throws {
        let newer = Data(#"{"schemaVersion":2,"profiles":"a shape this build does not know"}"#.utf8)
        await fileStore.place(newer, at: fileURL)
        let store = makeStore()
        let refusal = StoreError.unsupportedSchemaVersion(found: 2, supported: SchemaVersion.current)

        await #expect(throws: refusal) { try await store.loadProfiles() }
        await #expect(throws: refusal) { try await store.saveProfiles([ProfileBuilder().build()]) }

        #expect(await fileStore.contents(of: fileURL) == newer)
        #expect(await fileStore.contents(of: corruptCopyURL) == nil)
        #expect(await !fileStore.operations.contains(.write("profiles.json")))
    }

    @Test(arguments: corruptedContents)
    func undecodableOrInvalidFileIsReportedAsCorrupted(contents: String) async {
        await fileStore.place(Data(contents.utf8), at: fileURL)

        await #expect {
            try await makeStore().loadProfiles()
        } throws: { error in
            guard case .corrupted(let fileName, _) = error as? StoreError else {
                return false
            }
            return fileName == "profiles.json"
        }
    }

    @Test(arguments: corruptedContents)
    func saveOverCorruptedFileKeepsByteIdenticalCopyThenWrites(contents: String) async throws {
        let corrupted = Data(contents.utf8)
        await fileStore.place(corrupted, at: fileURL)
        let store = makeStore()
        let profile = ProfileBuilder().build()

        try await store.saveProfiles([profile])

        #expect(await fileStore.contents(of: corruptCopyURL) == corrupted)
        #expect(try await store.loadProfiles() == [profile])
    }

    @Test
    func laterCorruptionReplacesTheEarlierCopy() async throws {
        let store = makeStore()
        await fileStore.place(Data("first damage".utf8), at: fileURL)
        try await store.saveProfiles([ProfileBuilder().build()])
        await fileStore.place(Data("second damage".utf8), at: fileURL)

        try await store.saveProfiles([ProfileBuilder().build()])

        #expect(await fileStore.contents(of: corruptCopyURL) == Data("second damage".utf8))
    }

    @Test
    func failedCopyOfCorruptedFileAbortsTheSave() async {
        let corrupted = Data("{".utf8)
        await fileStore.place(corrupted, at: fileURL)
        await fileStore.failNextWrite()

        await #expect {
            try await makeStore().saveProfiles([ProfileBuilder().build()])
        } throws: { error in
            guard case .ioFailure(let fileName, _) = error as? StoreError else {
                return false
            }
            return fileName == "profiles.json.corrupt"
        }

        #expect(await fileStore.contents(of: fileURL) == corrupted)
    }
}
