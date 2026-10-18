import Foundation
import ModeKit
import Testing

struct ProfileStoreTests {
    private let directory = URL(filePath: "/Store")
    private let fileStore = InMemoryFileStore()
    private var fileURL: URL { directory.appending(path: "profiles.json") }

    private func makeStore() -> ProfileStore {
        ProfileStore(fileStore: fileStore, directory: directory)
    }

    @Test
    func loadReturnsEmptyArrayWhenFileIsMissing() async throws {
        #expect(try await makeStore().loadProfiles().isEmpty)
    }

    @Test
    func handWrittenExampleDecodesToExpectedProfile() async throws {
        await fileStore.place(Data(ProfilesFileFixture.handWritten.utf8), at: fileURL)

        let profiles = try await makeStore().loadProfiles()

        let expected = ProfileBuilder(
            steps: [
                .hideDesktopIcons, .hideDock, .hideMenuBar,
                .hideApps(exclusions: [try BundleIdentifier("com.apple.Safari")]),
                .wallpaper(.solidColor(SolidColor(red: 21, green: 21, blue: 21)), displays: .allDisplays),
            ],
            autoExit: try AutoExit(seconds: 1_800),
        )
        .build()
        #expect(profiles == [expected])
    }

    @Test
    func reencodingTheExampleIsByteIdenticalToSortedFixture() async throws {
        await fileStore.place(Data(ProfilesFileFixture.handWritten.utf8), at: fileURL)
        let store = makeStore()

        try await store.saveProfiles(try await store.loadProfiles())

        let written = try #require(await fileStore.contents(of: fileURL))
        #expect(written == Data(ProfilesFileFixture.written.utf8))
    }

    @Test
    func saveThenLoadReturnsProfilesWithTrimmedNames() async throws {
        let store = makeStore()
        let first = ProfileBuilder(name: "  Запись экрана 🎥 ").build()
        let second = ProfileBuilder(id: UUID(), name: "Meeting", steps: []).build()

        try await store.saveProfiles([first, second])

        let loaded = try await store.loadProfiles()
        #expect(loaded.map(\.name) == ["Запись экрана 🎥", "Meeting"])
        #expect(loaded.map(\.id) == [first.id, second.id])
    }

    @Test
    func saveRejectsInvalidProfileAndWritesNothing() async {
        let store = makeStore()

        await #expect(throws: StoreError.invalidProfile(.emptyName)) {
            try await store.saveProfiles([ProfileBuilder(name: " ").build()])
        }
        #expect(await fileStore.operations.isEmpty)
    }

    @Test
    func saveRejectsDuplicateProfileIDs() async {
        let profile = ProfileBuilder().build()

        await #expect(throws: StoreError.duplicateProfileID(profile.id)) {
            try await makeStore().saveProfiles([profile, ProfileBuilder(name: "Other").build()])
        }
        #expect(await fileStore.operations.isEmpty)
    }

    @Test
    func failedWriteReportsIOFailureAndKeepsPreviousFile() async throws {
        let store = makeStore()
        try await store.saveProfiles([ProfileBuilder().build()])
        let previous = await fileStore.contents(of: fileURL)
        await fileStore.failNextWrite()

        await #expect(throws: StoreError.self) {
            try await store.saveProfiles([ProfileBuilder(name: "Changed").build()])
        }

        #expect(await fileStore.contents(of: fileURL) == previous)
    }

    @Test
    func failedReadReportsIOFailureWithFileNameOnly() async {
        await fileStore.failNextRead()

        await #expect {
            try await makeStore().loadProfiles()
        } throws: { error in
            guard case .ioFailure(let fileName, let reason) = error as? StoreError else {
                return false
            }
            return fileName == "profiles.json" && !reason.contains("/Store")
        }
    }

    @Test
    func concurrentSavesRunOneAfterAnother() async throws {
        let store = makeStore()
        let first = ProfileBuilder(name: "First").build()
        let second = ProfileBuilder(name: "Second").build()

        async let firstSave: Void = store.saveProfiles([first])
        async let secondSave: Void = store.saveProfiles([second])
        _ = try await (firstSave, secondSave)

        let operations = await fileStore.operations
        let oneSave: [InMemoryFileStore.Operation] = [.read("profiles.json"), .write("profiles.json")]
        #expect(operations == oneSave + oneSave)
        let names = try await store.loadProfiles().map(\.name)
        #expect(names == ["First"] || names == ["Second"])
    }
}
