#if DEBUG
import Foundation
import Testing

@testable import PresenterApp

struct StoreStructureTests {
    @Test
    func theStructureShowsNamesAndKindsButNoValuesOrUUIDs() throws {
        let store = try PropertyListValue.decode(
            WallpaperStoreFixture.data(named: WallpaperStoreFixture.currentCustomColor))

        let lines = StoreStructure.lines(of: store)

        #expect(lines.first == "AllSpacesAndDisplays: string")
        #expect(lines.contains("Displays: dictionary"))
        #expect(lines.contains("  <1 UUID keys>: dictionary, first:"))
        #expect(lines.contains { $0.hasSuffix("Provider: string") })
        #expect(lines.contains { $0.hasSuffix("(nested)") })
        #expect(lines.contains("  \"\": dictionary"))
        #expect(!lines.contains { $0.contains("00000000-") || $0.contains("com.apple.wallpaper.choice") })
    }

    @Test
    func anEmptyArrayAndEveryKindHaveALabel() {
        let value = PropertyListValue.dictionary([
            "list": .array([]),
            "flag": .boolean(true),
            "count": .integer(1),
            "share": .real(0.5),
            "when": .date(.distantPast),
            "bytes": .data(Data()),
        ])

        #expect(
            StoreStructure.lines(of: value) == [
                "bytes: data", "count: integer", "flag: boolean", "list: array", "  [0 items]", "share: real",
                "when: date",
            ])
    }
}
#endif
