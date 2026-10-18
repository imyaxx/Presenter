import Foundation
import Testing

@testable import ModeKit

struct WallpaperRestorerTests {
    private typealias Snapshot = WallpaperRestorer.Snapshot
    private typealias Applied = WallpaperRestorer.AppliedState
    private static let storeURL = URL(filePath: "/fake/wallpaper/Index.plist")
    private static let display = DisplayIdentifier(
        uuid: UUID(uuidString: "0D6F9C2A-5B43-4E1D-9A57-3C8E2F1B7A60") ?? UUID())
    private static let killallWallpaperAgent = ProcessCommand(
        executableURL: URL(filePath: "/usr/bin/killall"),
        arguments: ["WallpaperAgent"],
        timeout: .seconds(10),
    )
    private static let original = FakeWallpaperStore.encode([display: "color 0.0823 0.0823 0.0823"], lastUse: 3)
    private static let blueImage = "image /fake/support/wallpapers/solid-1e90ff.png"
    private static let applied = FakeWallpaperStore.encode([display: blueImage], lastUse: 4)

    private let files = InMemoryFileStore()
    private let processRunner = FakeProcessRunner()

    private func makeRestorer(
        inspector: FakeWallpaperStoreInspector = FakeWallpaperStoreInspector()
    ) -> WallpaperRestorer {
        WallpaperRestorer(
            fileStore: files,
            processRunner: processRunner,
            storeInspector: inspector,
            storeURL: Self.storeURL,
        )
    }

    private func restoreOriginal(expecting applied: Applied?) async throws -> RestoreOutcome {
        try await makeRestorer().restore(Snapshot(storeData: Self.original), expecting: applied)
    }

    private func appliedState() throws -> Applied {
        Applied(displays: [Self.display], fingerprint: try FakeWallpaperStoreInspector().fingerprint(of: Self.applied))
    }

    // Per-action scenario: restore returns to the captured state
    @Test
    func restoreWritesTheSnapshotBytesExactlyThenRestartsTheAgent() async throws {
        await files.place(Self.applied, at: Self.storeURL)

        let outcome = try await restoreOriginal(expecting: try appliedState())

        #expect(outcome == .restored)
        #expect(await files.contents(of: Self.storeURL) == Self.original)
        #expect(await files.operations == [.read("Index.plist"), .write("Index.plist")])
        #expect(await processRunner.commands == [Self.killallWallpaperAgent])
        #expect(WallpaperRestorer.restartWallpaperAgent.executableURL.path(percentEncoded: false) == "/usr/bin/killall")
        #expect(WallpaperRestorer.restartWallpaperAgent.arguments == ["WallpaperAgent"])
        #expect(WallpaperRestorer.restartWallpaperAgent.timeout == .seconds(10))
    }

    @Test(arguments: [
        "color 0.0823 0.0823 0.0823", "dynamic com.apple.wallpaper.choice.sequoia", "image /Users/x/a.jpg",
    ])
    func anyOriginalWallpaperIsRestoredFromTheStoreBytes(original: String) async throws {
        let snapshot = FakeWallpaperStore.encode([Self.display: original], lastUse: 1)
        await files.place(Self.applied, at: Self.storeURL)

        _ = try await makeRestorer().restore(Snapshot(storeData: snapshot), expecting: try appliedState())

        #expect(await files.contents(of: Self.storeURL) == snapshot)
    }

    @Test
    func aChangeOfOnlyTheVolatilePartIsNotAChangeByTheUser() async throws {
        await files.place(
            FakeWallpaperStore.encode([Self.display: Self.blueImage], lastUse: 9),
            at: Self.storeURL,
        )

        let outcome = try await restoreOriginal(expecting: try appliedState())

        #expect(outcome == .restored)
        #expect(await files.contents(of: Self.storeURL) == Self.original)
    }

    // Per-action scenario: state already equal to the target
    @Test
    func restoreWhenTheStoreAlreadyHoldsTheSnapshotDoesNothing() async throws {
        await files.place(Self.original, at: Self.storeURL)

        let outcome = try await restoreOriginal(expecting: try appliedState())

        #expect(outcome == .restored)
        #expect(await files.operations == [.read("Index.plist")])
        #expect(await processRunner.commands.isEmpty)
    }

    // Per-action scenario: restore skips when changed
    @Test
    func restoreIsSkippedWhenTheUserChangedTheWallpaper() async throws {
        let userChoice = FakeWallpaperStore.encode(
            [Self.display: "dynamic com.apple.wallpaper.choice.sequoia"], lastUse: 5, )
        await files.place(userChoice, at: Self.storeURL)

        let outcome = try await restoreOriginal(expecting: try appliedState())

        #expect(outcome == .skippedBecauseChangedByUser)
        #expect(await files.contents(of: Self.storeURL) == userChoice)
        #expect(await processRunner.commands.isEmpty)
    }

    @Test
    func restoreWithoutAppliedStateWritesUnconditionally() async throws {
        let userChoice = FakeWallpaperStore.encode(
            [Self.display: "dynamic com.apple.wallpaper.choice.sequoia"], lastUse: 5, )
        await files.place(userChoice, at: Self.storeURL)

        let outcome = try await restoreOriginal(expecting: nil)

        #expect(outcome == .restored)
        #expect(await files.contents(of: Self.storeURL) == Self.original)
        #expect(await processRunner.commands == [Self.killallWallpaperAgent])
    }

    @Test
    func restoreFailsWhenTheStoreIsMissing() async throws {
        await #expect(throws: WallpaperActionError.storeUnavailable) {
            try await restoreOriginal(expecting: try appliedState())
        }
    }

    // Per-action scenario: the system call fails
    @Test
    func aFailingStoreWriteFailsTheRestoreWithoutRestartingTheAgent() async throws {
        await files.place(Self.applied, at: Self.storeURL)
        await files.failNextWrite()

        await #expect(throws: InMemoryFileStore.InjectedFailure()) {
            try await restoreOriginal(expecting: try appliedState())
        }
        #expect(await files.contents(of: Self.storeURL) == Self.applied)
        #expect(await processRunner.commands.isEmpty)
    }

    @Test(arguments: [Int32(0), 1])
    func killallExitZeroOrOneIsSuccess(exitCode: Int32) async throws {
        await files.place(Self.applied, at: Self.storeURL)
        await processRunner.script(Self.killallWallpaperAgent, .success(ProcessResult(exitCode: exitCode)))

        #expect(try await restoreOriginal(expecting: nil) == .restored)
    }

    // Per-action scenario: the system call fails, and timeout
    @Test(arguments: [
        (Result<ProcessResult, any Error>.success(ProcessResult(exitCode: 2)), "killall WallpaperAgent exited with 2"),
        (.failure(ProcessError.timedOut(.seconds(10))), ProcessError.timedOut(.seconds(10)).description),
    ])
    func killallFailureFailsTheRestore(result: Result<ProcessResult, any Error>, diagnostic: String) async {
        await files.place(Self.applied, at: Self.storeURL)
        await processRunner.script(Self.killallWallpaperAgent, result)

        await #expect {
            try await restoreOriginal(expecting: nil)
        } throws: { error in
            String(describing: error) == diagnostic
        }
        #expect(await files.contents(of: Self.storeURL) == Self.original)
    }

    @Test
    func anInspectorFailureDuringTheConditionalCheckFailsTheRestore() async throws {
        await files.place(Self.applied, at: Self.storeURL)
        let error = WallpaperStoreError.unrecognizedFormat(reason: "new macOS format")

        await #expect(throws: error) {
            try await makeRestorer(inspector: FakeWallpaperStoreInspector(failure: error))
                .restore(Snapshot(storeData: Self.original), expecting: try appliedState())
        }
        #expect(await files.contents(of: Self.storeURL) == Self.applied)
        #expect(await processRunner.commands.isEmpty)
    }

    @Test
    func theSnapshotAndAppliedStateRoundTripThroughPersistenceCodingWithALargeStore() throws {
        let storeData = Data((0..<500_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let snapshot = Snapshot(storeData: storeData)
        let applied = try appliedState()

        let encoder = PersistenceCoding.makeEncoder()
        let decoder = PersistenceCoding.makeDecoder()

        #expect(try decoder.decode(Snapshot.self, from: encoder.encode(snapshot)) == snapshot)
        #expect(try decoder.decode(Applied.self, from: encoder.encode(applied)) == applied)
    }

    @Test
    func errorsDescribeThemselves() {
        #expect(WallpaperActionError.storeUnavailable.description == "The wallpaper store file does not exist")
        #expect(
            WallpaperActionError.storeDidNotChange.description
                == "The wallpaper store did not change after the desktop image was set")
        #expect(
            WallpaperActionError.wallpaperAgentRestartFailed(exitCode: 3).description
                == "killall WallpaperAgent exited with 3")
        #expect(
            WallpaperStoreError.unrecognizedFormat(reason: "x").description
                == "Wallpaper store format not recognized: x")
    }
}
