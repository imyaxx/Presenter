#if DEBUG
import CryptoKit
import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Reads injected stubs only; nothing of the real system.
struct WorldReaderTests {
    private static let storeURL = URL(filePath: "/stub/Index.plist")
    private static let store = Data("store".utf8)
    private static let left = DisplayIdentifier(
        uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID())
    private static let right = DisplayIdentifier(
        uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID())

    private func reader(
        defaults: StubDefaultsStore,
        files: [URL: Data] = [storeURL: store],
        fingerprint: WallpaperStoreFingerprint? = WallpaperStoreFingerprint(data: Data([0xAB, 0x01])),
    ) throws -> WorldReader {
        let workspace = StubWorkspace(
            applications: [
                try Stub.application("com.example.zeta", hidden: .hidden),
                try Stub.application("com.example.alpha", frontmost: .frontmost),
            ],
            displays: [Self.left, Self.right],
        )
        return WorldReader(
            defaults: defaults,
            fileStore: StubFileStore(files: files),
            storeInspector: StubInspector(fingerprint: fingerprint),
            workspace: workspace,
            storeURL: Self.storeURL,
            macOSVersion: "Version 27.0.1",
        )
    }

    @Test
    func theSnapshotHoldsTheKeysTheStoreTheApplicationsAndTheDisplays() async throws {
        let defaults = StubDefaultsStore(values: [
            DefaultsKey(domain: "com.apple.dock", name: "autohide"): .bool(true),
            DefaultsKey(domain: "com.apple.controlcenter", name: "AutoHideMenuBarOption"): .integer(2),
        ])

        let world = try await reader(defaults: defaults).read()

        #expect(world.schemaVersion == 1)
        #expect(world.macOSVersion == "Version 27.0.1")
        #expect(world.keys.map(\.type) == ["absent", "boolean", "integer", "absent", "absent"])
        #expect(world.keys.map(\.value) == [nil, "true", "2", nil, nil])
        #expect(world.wallpaperStore.size == 5)
        #expect(world.wallpaperStore.sha256 == WorldReader.hex(Data(SHA256.hash(data: Self.store))))
        #expect(world.wallpaperStore.fingerprint == "ab01")
        #expect(world.applications.map(\.bundleIdentifier) == ["com.example.alpha", "com.example.zeta"])
        #expect(world.applications.map(\.isHidden) == [false, true])
        #expect(world.frontmostApplication == "com.example.alpha")
        #expect(world.displays == ["00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002"])
    }

    @Test
    func anUnreadableKeyIsReportedNotThrown() async throws {
        let key = DefaultsKey(domain: "com.apple.finder", name: "CreateDesktop")
        let defaults = StubDefaultsStore(values: [:], unreadable: [key])

        let world = try await reader(defaults: defaults).read()

        #expect(world.keys.first?.type == "unreadable")
    }

    @Test
    func aMissingStoreAndAnUnrecognizedStoreAreReported() async throws {
        let missing = try await reader(defaults: StubDefaultsStore(values: [:]), files: [:]).read()
        let unrecognized = try await reader(defaults: StubDefaultsStore(values: [:]), fingerprint: nil).read()

        #expect(
            missing.wallpaperStore
                == WorldSnapshot.WallpaperStore(size: nil, sha256: nil, fingerprint: nil, error: "absent"))
        #expect(unrecognized.wallpaperStore.fingerprint == nil)
        #expect(unrecognized.wallpaperStore.error == "Wallpaper store format not recognized: stub")
    }

    @Test
    func theSnapshotRoundTripsAsJSON() async throws {
        let world = try await reader(defaults: StubDefaultsStore(values: [:])).read()

        let decoded = try JSONDecoder().decode(WorldSnapshot.self, from: JSONEncoder().encode(world))

        #expect(decoded == world)
    }
}
#endif
