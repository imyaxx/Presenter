#if DEBUG
import CryptoKit
import Foundation
import ModeKit

/// Reads a ``WorldSnapshot`` through the ports, so tests inject fakes and nothing is changed.
struct WorldReader: Sendable {
    /// The five preference keys the actions use (desktop icons, Dock, menu bar), in that order.
    static let actionKeys = [
        DefaultsKey(domain: "com.apple.finder", name: "CreateDesktop"),
        DefaultsKey(domain: "com.apple.dock", name: "autohide"),
        DefaultsKey(domain: "com.apple.controlcenter", name: "AutoHideMenuBarOption"),
        DefaultsKey(domain: "NSGlobalDomain", name: "_HIHideMenuBar"),
        DefaultsKey(domain: "NSGlobalDomain", name: "AppleMenuBarVisibleInFullscreen"),
    ]

    let defaults: any DefaultsStore
    let fileStore: any FileStore
    let storeInspector: any WallpaperStoreInspector
    let workspace: any WorkspaceAdapter
    let storeURL: URL
    let macOSVersion: String

    func read() async -> WorldSnapshot {
        var keys: [WorldSnapshot.Key] = []
        for key in Self.actionKeys {
            keys.append(await read(key))
        }
        let running = await workspace.runningApplications()
        return WorldSnapshot(
            schemaVersion: WorldSnapshot.currentSchemaVersion,
            macOSVersion: macOSVersion,
            keys: keys,
            wallpaperStore: await readStore(),
            applications: running.map {
                WorldSnapshot.Application(bundleIdentifier: $0.bundleIdentifier.rawValue, isHidden: $0.isHidden)
            }.sorted(),
            frontmostApplication: running.first(where: \.isFrontmost)?.bundleIdentifier.rawValue,
            displays: await workspace.connectedDisplays().map(\.uuid.uuidString).sorted(),
        )
    }

    private func read(_ key: DefaultsKey) async -> WorldSnapshot.Key {
        do {
            switch try await defaults.value(for: key) {
            case nil: return WorldSnapshot.Key(domain: key.domain, name: key.name, type: "absent", value: nil)
            case .bool(let value)?:
                return WorldSnapshot.Key(domain: key.domain, name: key.name, type: "boolean", value: "\(value)")
            case .integer(let value)?:
                return WorldSnapshot.Key(domain: key.domain, name: key.name, type: "integer", value: "\(value)")
            }
        } catch {
            return WorldSnapshot.Key(domain: key.domain, name: key.name, type: "unreadable", value: "\(error)")
        }
    }

    private func readStore() async -> WorldSnapshot.WallpaperStore {
        let data: Data
        do {
            guard let stored = try await fileStore.read(storeURL) else {
                return WorldSnapshot.WallpaperStore(size: nil, sha256: nil, fingerprint: nil, error: "absent")
            }
            data = stored
        } catch {
            return WorldSnapshot.WallpaperStore(size: nil, sha256: nil, fingerprint: nil, error: "\(error)")
        }
        let digest = Self.hex(Data(SHA256.hash(data: data)))
        do {
            let fingerprint = try storeInspector.fingerprint(of: data)
            return WorldSnapshot.WallpaperStore(
                size: data.count,
                sha256: digest,
                fingerprint: Self.hex(fingerprint.data),
                error: nil,
            )
        } catch {
            return WorldSnapshot.WallpaperStore(
                size: data.count, sha256: digest, fingerprint: nil, error: "\(error)", )
        }
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
