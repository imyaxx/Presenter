import Foundation

/// Sanitized wallpaper stores under `App/Tests/Fixtures/WallpaperStore`, made with
/// `Scripts/sanitize-wallpaper-store.swift` from the store of the development Mac and from spike S2 copies, and edits
/// of them for tests. Read from the source tree, like the string catalog tests.
enum WallpaperStoreFixture {
    /// The live store of the development Mac: one display, a custom color, 44 Spaces (2026-10-18).
    static let currentCustomColor = "current-custom-color.plist"
    /// Spike S2 baseline: one display, a custom color, 40 Spaces.
    static let baselineCustomColor = "s2-baseline-custom-color.plist"
    /// Spike S2 copy with a dynamic wallpaper: `individual` entries with `Desktop` and `Idle` content.
    static let dynamicWithIdleImage = "s2-dynamic-with-idle-image.plist"
    static let all = [currentCustomColor, baselineCustomColor, dynamicWithIdleImage]

    static func data(named name: String) throws -> Data {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/WallpaperStore/\(name)")
        return try Data(contentsOf: url)
    }

    static func store(named name: String) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data(named: name), format: nil)
        return object as? [String: Any] ?? [:]
    }

    static func encode(_ store: [String: Any], as format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: store, format: format, options: 0)
    }

    /// Replaces the value of every dictionary entry named `key`, at any depth, nested binary property lists included.
    static func replacing(_ key: String, in value: Any, with replacement: (Any) -> Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            var result: [String: Any] = [:]
            for (entryKey, entryValue) in dictionary {
                let edited = replacing(key, in: entryValue, with: replacement)
                result[entryKey] = entryKey == key ? replacement(edited) : edited
            }
            return result
        case let array as [Any]:
            return array.map { replacing(key, in: $0, with: replacement) }
        case let data as Data:
            guard data.starts(with: Data("bplist".utf8)),
                let nested = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let encoded = try? PropertyListSerialization.data(
                    fromPropertyList: replacing(key, in: nested, with: replacement),
                    format: .binary,
                    options: 0,
                )
            else {
                return data
            }
            return encoded
        default:
            return value
        }
    }

    /// Every string found at any depth, dictionary keys and nested binary property lists included.
    static func strings(in value: Any) -> [String] {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.flatMap { [$0.key] + strings(in: $0.value) }
        case let array as [Any]:
            return array.flatMap(strings(in:))
        case let string as String:
            return [string]
        case let data as Data:
            guard data.starts(with: Data("bplist".utf8)),
                let nested = try? PropertyListSerialization.propertyList(from: data, format: nil)
            else {
                // Latin-1 decodes any bytes, so opaque data is still searched for personal strings.
                return String(bytes: data, encoding: .isoLatin1).map { [$0] } ?? []
            }
            return strings(in: nested)
        default:
            return []
        }
    }
}
