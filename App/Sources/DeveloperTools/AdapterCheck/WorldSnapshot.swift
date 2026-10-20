#if DEBUG
import Foundation

/// A read-only picture of everything the actions touch, written by `world` (docs/13-adapter-check.md).
///
/// `applications` and `displays` are sorted so two snapshots compare as text; the frontmost application is kept apart
/// because it changes with the user's focus. Contains local data (identifiers, display UUIDs): it is written only
/// under the check directory.
struct WorldSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct Key: Codable, Equatable, Sendable {
        let domain: String
        let name: String
        /// `boolean`, `integer`, `absent`, or `unreadable` with the error in `value`.
        let type: String
        let value: String?
    }

    struct WallpaperStore: Codable, Equatable, Sendable {
        let size: Int?
        let sha256: String?
        /// The inspector's fingerprint as hex, when the inspector recognizes the store.
        let fingerprint: String?
        let error: String?
    }

    struct Application: Codable, Equatable, Comparable, Sendable {
        let bundleIdentifier: String
        let isHidden: Bool

        static func < (lhs: Application, rhs: Application) -> Bool {
            (lhs.bundleIdentifier, lhs.isHidden ? 1 : 0) < (rhs.bundleIdentifier, rhs.isHidden ? 1 : 0)
        }
    }

    let schemaVersion: Int
    let macOSVersion: String
    let keys: [Key]
    let wallpaperStore: WallpaperStore
    let applications: [Application]
    let frontmostApplication: String?
    let displays: [String]
}
#endif
