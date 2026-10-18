import Foundation
import ModeKit
import Testing

struct ProfileStepCodingTests {
    private static let displayID = DisplayIdentifier(
        uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID()
    )

    static let everyStepKind: [ProfileStep] = [
        .hideDesktopIcons,
        .hideDock,
        .hideMenuBar,
        .hideApps(exclusions: []),
        .wallpaper(.solidColor(SolidColor(red: 21, green: 21, blue: 21)), displays: .allDisplays),
        .wallpaper(.image(URL(filePath: "/Users/someone/Pictures/неон 🌃.png")), displays: .specific([displayID])),
    ]

    @Test(arguments: everyStepKind)
    func stepRoundTripsThroughJSON(step: ProfileStep) throws {
        let data = try JSONEncoder().encode(step)

        #expect(try JSONDecoder().decode(ProfileStep.self, from: data) == step)
    }

    @Test
    func hideAppsWithExclusionsRoundTrips() throws {
        let step = ProfileStep.hideApps(exclusions: [try BundleIdentifier("com.apple.Safari")])

        #expect(try JSONDecoder().decode(ProfileStep.self, from: JSONEncoder().encode(step)) == step)
    }

    @Test
    func exclusionsAreEncodedAsSortedArray() throws {
        let step = ProfileStep.hideApps(exclusions: [
            try BundleIdentifier("org.mozilla.firefox"),
            try BundleIdentifier("com.apple.Safari"),
            try BundleIdentifier("com.apple.Music"),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = try #require(String(bytes: try encoder.encode(step), encoding: .utf8))

        let expected = #"{"exclusions":["com.apple.Music","com.apple.Safari","org.mozilla.firefox"],"type":"hideApps"}"#
        #expect(json == expected)
    }

    @Test(arguments: [
        #"{"type":"hideEverything"}"#,
        #"{"type":"wallpaper","choice":{"type":"gradient"},"displays":{"type":"allDisplays"}}"#,
        #"{"type":"wallpaper","choice":{"type":"image","path":"/a.png"},"displays":{"type":"someDisplays"}}"#,
        #"{"steps":[]}"#,
    ])
    func decodingRejectsUnknownTypeOrMissingDiscriminator(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProfileStep.self, from: Data(json.utf8))
        }
    }

    @Test
    func decodingRejectsRelativeImagePath() {
        let json = #"{"type":"image","path":"Pictures/a.png"}"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WallpaperChoice.self, from: Data(json.utf8))
        }
    }

    @Test
    func decodingRejectsInvalidBundleIdentifierInExclusions() {
        let json = #"{"type":"hideApps","exclusions":["not a bundle id"]}"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProfileStep.self, from: Data(json.utf8))
        }
    }

    @Test
    func actionIdentifierMapsEveryStepKind() {
        let identifiers = Self.everyStepKind.map(\.actionIdentifier)

        #expect(identifiers == [.desktopIcons, .dock, .menuBar, .hideApps, .wallpaper, .wallpaper])
    }
}
