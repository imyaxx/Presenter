import AppKit
import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Works on sanitized fixtures only; never reads or writes the real wallpaper store (ADR-040, ADR-041).
struct PropertyListWallpaperStoreInspectorTests {
    private typealias Fixture = WallpaperStoreFixture
    private static let placeholderUUIDPrefix = "00000000-0000-0000-0000-"

    private let inspector = PropertyListWallpaperStoreInspector()

    private func fingerprint(_ store: [String: Any]) throws -> WallpaperStoreFingerprint {
        try inspector.fingerprint(of: Fixture.encode(store, as: .binary))
    }

    @Test(arguments: Fixture.all)
    @MainActor
    func fixturesContainNoPersonalData(name: String) throws {
        let strings = Fixture.strings(in: try Fixture.store(named: name))
        let displayUUIDs = NSScreen.screens.compactMap(DisplayIdentifierMapping.identifier(of:)).map(\.uuid.uuidString)
        let uuidPattern = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/

        #expect(!strings.isEmpty)
        for string in strings {
            #expect(!string.contains("/Users/"))
            #expect(!string.contains(NSUserName()))
            for match in string.matches(of: uuidPattern) {
                #expect(match.output.hasPrefix(Self.placeholderUUIDPrefix))
                #expect(!displayUUIDs.contains(String(match.output).uppercased()))
            }
        }
    }

    @Test(arguments: Fixture.all)
    func everyFixtureIsRecognized(name: String) throws {
        _ = try inspector.fingerprint(of: Fixture.data(named: name))
    }

    @Test
    func differentWallpapersGiveDifferentFingerprints() throws {
        let color = try inspector.fingerprint(of: Fixture.data(named: Fixture.currentCustomColor))
        let dynamic = try inspector.fingerprint(of: Fixture.data(named: Fixture.dynamicWithIdleImage))

        #expect(color != dynamic)
    }

    @Test(arguments: Fixture.all)
    func changedTimestampsDoNotChangeTheFingerprint(name: String) throws {
        let store = try Fixture.store(named: name)
        let later = Date(timeIntervalSince1970: 1_800_000_000)
        var touched = store
        for key in ["LastUse", "LastSet"] {
            touched = Fixture.replacing(key, in: touched, with: { _ in later }) as? [String: Any] ?? [:]
        }

        #expect(try fingerprint(touched) == fingerprint(store))
    }

    @Test(arguments: Fixture.all)
    func aChangedProviderChangesTheFingerprint(name: String) throws {
        let store = try Fixture.store(named: name)
        let edited = try #require(
            Fixture.replacing("Provider", in: store, with: { _ in "com.apple.wallpaper.choice.image" })
                as? [String: Any])

        #expect(try fingerprint(edited) != fingerprint(store))
    }

    @Test(arguments: Fixture.all)
    func aChangedConfigurationChangesTheFingerprint(name: String) throws {
        let store = try Fixture.store(named: name)
        let configuration = try Fixture.encode(["type": "imageFile"], as: .binary)
        let edited = try #require(
            Fixture.replacing("Configuration", in: store, with: { _ in configuration }) as? [String: Any])

        #expect(try fingerprint(edited) != fingerprint(store))
    }

    @Test(arguments: Fixture.all)
    func aNewSpaceEntryDoesNotChangeTheFingerprint(name: String) throws {
        let store = try Fixture.store(named: name)
        var spaces = try #require(store["Spaces"] as? [String: Any])
        spaces["00000000-0000-0000-0000-FFFFFFFFFFFF"] = spaces[""]
        var edited = store
        edited["Spaces"] = spaces

        #expect(try fingerprint(edited) == fingerprint(store))
    }

    /// Regression for adapter check C7 (2026-10-20): `WallpaperAgent` rewrote `Displays` and `SystemDefault` by itself
    /// after a restart, and the restore took that for a change by the user.
    @Test(arguments: Fixture.all)
    func changesOutsideTheAllSpacesEntryDoNotChangeTheFingerprint(name: String) throws {
        let store = try Fixture.store(named: name)
        var edited = store
        edited["Displays"] = ["00000000-0000-0000-0000-00000000FFFF": ["Type": "individual"]]
        edited["SystemDefault"] = ["Type": "individual"]

        #expect(try fingerprint(edited) == fingerprint(store))
    }

    @Test
    func theAllSpacesEntryCountsAndMayBeAbsent() throws {
        let store = try Fixture.store(named: Fixture.currentCustomColor)
        var spaces = try #require(store["Spaces"] as? [String: Any])
        spaces[""] = nil
        var edited = store
        edited["Spaces"] = spaces

        #expect(try fingerprint(edited) != fingerprint(store))
    }

    @Test(arguments: Fixture.all)
    func theEncodingDoesNotChangeTheFingerprint(name: String) throws {
        let store = try Fixture.store(named: name)

        #expect(try inspector.fingerprint(of: Fixture.encode(store, as: .xml)) == fingerprint(store))
    }

    @Test
    func theFingerprintIsADigestNotTheStore() throws {
        let fingerprint = try inspector.fingerprint(of: Fixture.data(named: Fixture.currentCustomColor))

        #expect(fingerprint.data.count == 32)
    }

    @Test(arguments: [
        (Data(), "not a property list"),
        // A bare "bplist00" header parses as an old-style text string, so the header is followed by invalid bytes.
        (Data("bplist00".utf8) + Data([0xFF, 0xFE, 0x00]), "not a property list"),
        (Data("<plist><array/></plist>".utf8), "the top level is not a dictionary"),
    ])
    func malformedDataFailsClosed(data: Data, reason: String) {
        #expect(throws: WallpaperStoreError.unrecognizedFormat(reason: reason)) { try inspector.fingerprint(of: data) }
    }

    @Test
    func aTruncatedStoreFailsClosed() throws {
        let data = try Fixture.data(named: Fixture.currentCustomColor)

        #expect(throws: WallpaperStoreError.unrecognizedFormat(reason: "not a property list")) {
            try inspector.fingerprint(of: data.prefix(data.count / 2))
        }
    }

    enum WrongShape: CaseIterable, Sendable {
        case noDisplays, displaysNotADictionary, noSpaces, allSpacesNotADictionary

        var store: [String: Any] {
            switch self {
            case .noDisplays: ["Spaces": [String: Any]()]
            case .displaysNotADictionary: ["Displays": "x", "Spaces": [String: Any]()]
            case .noSpaces: ["Displays": [String: Any]()]
            case .allSpacesNotADictionary: ["Displays": [String: Any](), "Spaces": ["": "x"]]
            }
        }

        var reason: String {
            switch self {
            case .noDisplays, .displaysNotADictionary: "no Displays dictionary"
            case .noSpaces: "no Spaces dictionary"
            case .allSpacesNotADictionary: "the all-Spaces entry is not a dictionary"
            }
        }
    }

    @Test(arguments: WrongShape.allCases)
    func aStoreOfTheWrongShapeFailsClosed(shape: WrongShape) throws {
        #expect(throws: WallpaperStoreError.unrecognizedFormat(reason: shape.reason)) { try fingerprint(shape.store) }
    }
}
