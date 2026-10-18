import Foundation
import Testing

struct LocalizationCatalogTests {
    private static let sourceLanguage = "en"
    private static let requiredLanguages = ["en", "ru"]
    private static let catalogs = ["Localizable.xcstrings", "InfoPlist.xcstrings"]

    @Test(arguments: catalogs)
    func sourceLanguageIsEnglish(catalogName: String) throws {
        let catalog = try StringCatalog.loadAppCatalog(named: catalogName)

        #expect(catalog.sourceLanguage == Self.sourceLanguage)
    }

    @Test(arguments: catalogs)
    func everyKeyHasNonEmptyValueInEveryRequiredLanguage(catalogName: String) throws {
        let catalog = try StringCatalog.loadAppCatalog(named: catalogName)

        #expect(!catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            for language in Self.requiredLanguages {
                let value = entry.localizations?[language]?.stringUnit?.value ?? ""
                #expect(!value.isEmpty, "Key \(key) has no \(language) value")
            }
        }
    }

    @Test(arguments: catalogs)
    func everyKeyHasTranslatorComment(catalogName: String) throws {
        let catalog = try StringCatalog.loadAppCatalog(named: catalogName)

        for (key, entry) in catalog.strings {
            let comment = entry.comment ?? ""
            #expect(!comment.isEmpty, "Key \(key) has no translator comment")
        }
    }
}

/// The subset of the `.xcstrings` JSON format these tests inspect.
private struct StringCatalog: Decodable {
    struct Entry: Decodable {
        let comment: String?
        let localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        let stringUnit: StringUnit?
    }

    struct StringUnit: Decodable {
        let value: String
    }

    let sourceLanguage: String
    let strings: [String: Entry]

    /// Reads the catalog from the source tree, so the test checks the file that is committed.
    static func loadAppCatalog(named name: String) throws -> StringCatalog {
        let catalogURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/\(name)")
        let catalogData = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode(StringCatalog.self, from: catalogData)
    }
}
