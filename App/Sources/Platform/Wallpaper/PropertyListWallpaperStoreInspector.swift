import CryptoKit
import Foundation
import ModeKit

/// The real ``WallpaperStoreInspector`` for the wallpaper store `Index.plist` (ADR-039, ADR-041).
///
/// The fingerprint is the SHA-256 of the canonical text of the two parts `setDesktopImageURL` was observed to change
/// in spike S2: `Displays` (every display entry) and `Spaces[""]` (the entry for all Spaces). Nested binary property
/// lists are decoded, key order and encoding do not matter, and the timestamps `LastUse` and `LastSet` are left out at
/// every depth. Entries of individual Space UUIDs, `SystemDefault` and `AllSpacesAndDisplays` are left out, so a Space
/// created during a session is not a change by the user.
///
/// Fails closed: data that is not a property list, or whose top level is not a dictionary with `Displays` and `Spaces`
/// dictionaries, throws ``WallpaperStoreError/unrecognizedFormat(reason:)``.
///
/// Threading: a value type; a pure computation.
struct PropertyListWallpaperStoreInspector: WallpaperStoreInspector {
    static let volatileKeys: Set<String> = ["LastUse", "LastSet"]
    private static let displaysKey = "Displays"
    private static let spacesKey = "Spaces"
    private static let allSpacesKey = ""
    private static let absentMarker = "-"

    func fingerprint(of store: Data) throws -> WallpaperStoreFingerprint {
        let root: PropertyListValue
        do {
            root = try PropertyListValue.decode(store)
        } catch {
            throw WallpaperStoreError.unrecognizedFormat(reason: "not a property list")
        }
        guard case .dictionary(let top) = root else {
            throw WallpaperStoreError.unrecognizedFormat(reason: "the top level is not a dictionary")
        }
        guard case .dictionary? = top[Self.displaysKey] else {
            throw WallpaperStoreError.unrecognizedFormat(reason: "no Displays dictionary")
        }
        guard case .dictionary(let spaces)? = top[Self.spacesKey] else {
            throw WallpaperStoreError.unrecognizedFormat(reason: "no Spaces dictionary")
        }
        let displaysText = top[Self.displaysKey]?.canonicalText(excluding: Self.volatileKeys) ?? Self.absentMarker
        let allSpacesText = try Self.allSpacesText(spaces[Self.allSpacesKey])
        let canonical = displaysText + "|" + allSpacesText
        return WallpaperStoreFingerprint(data: Data(SHA256.hash(data: Data(canonical.utf8))))
    }

    private static func allSpacesText(_ entry: PropertyListValue?) throws -> String {
        guard let entry else {
            return absentMarker
        }
        guard case .dictionary = entry else {
            throw WallpaperStoreError.unrecognizedFormat(reason: "the all-Spaces entry is not a dictionary")
        }
        return entry.canonicalText(excluding: volatileKeys)
    }
}
