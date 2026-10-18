import Foundation
import ModeKit

/// A stateful model of the wallpaper store, held as one file in an ``InMemoryFileStore``.
///
/// It models spike S2 only coarsely and is not evidence about the real `Index.plist` format. Its content is text, one
/// item per line:
///
///     FakeWallpaperStore 1
///     display <display UUID> <wallpaper description>     one line per display, sorted by UUID
///     lastUse <counter>                                  volatile, like the real store's `LastUse` timestamps
///
/// ``agentReceived(_:on:)`` (called by ``FakeWorkspaceAdapter/setDesktopImage(_:on:)``) records a pending change that
/// the agent persists only after a configurable number of reads of the store, so the action's polling is exercised.
actor FakeWallpaperStore {
    enum Persistence: Sendable {
        /// The first `count` reads after a change still return the old content.
        case afterReads(Int)
        /// The agent never persists a change.
        case never
    }

    static let header = "FakeWallpaperStore 1"
    private static let displayPrefix = "display "
    private static let lastUsePrefix = "lastUse "

    let url: URL
    private let files: InMemoryFileStore
    private var persistence = Persistence.afterReads(0)
    private var pending: [DisplayIdentifier: String] = [:]
    private var readsBeforePersist = 0

    private init(files: InMemoryFileStore, url: URL) {
        self.files = files
        self.url = url
    }

    /// Places a store with `wallpapers` at `url` and hooks the reads of `files`.
    static func make(
        in files: InMemoryFileStore,
        at url: URL,
        wallpapers: [DisplayIdentifier: String],
    ) async -> FakeWallpaperStore {
        let store = FakeWallpaperStore(files: files, url: url)
        await files.place(encode(wallpapers, lastUse: 0), at: url)
        await files.onRead { readURL in await store.didRead(readURL) }
        return store
    }

    func persist(_ persistence: Persistence) {
        self.persistence = persistence
    }

    /// The agent received a desktop image for the current Space of `display`.
    func agentReceived(_ image: URL, on display: DisplayIdentifier) {
        pending[display] = "image \(image.path(percentEncoded: false))"
        if case .afterReads(let count) = persistence {
            readsBeforePersist = count
        }
    }

    /// The user chose a wallpaper in System Settings; the agent persists it at once.
    func userSets(_ wallpaper: String, on display: DisplayIdentifier) async {
        await write([display: wallpaper])
    }

    /// The agent updates only the volatile part, as it does when a wallpaper is shown again.
    func agentTouchesLastUse() async {
        await write([:])
    }

    /// The decoded wallpapers of the current content, for assertions.
    func wallpapers() async -> [DisplayIdentifier: String] {
        Self.decode(await files.contents(of: url) ?? Data()).wallpapers
    }

    private func didRead(_ readURL: URL) async {
        guard readURL == url, !pending.isEmpty, case .afterReads = persistence else {
            return
        }
        guard readsBeforePersist == 0 else {
            readsBeforePersist -= 1
            return
        }
        let changes = pending
        pending = [:]
        await write(changes)
    }

    private func write(_ changes: [DisplayIdentifier: String]) async {
        let current = Self.decode(await files.contents(of: url) ?? Data())
        let wallpapers = current.wallpapers.merging(changes) { _, new in new }
        await files.place(Self.encode(wallpapers, lastUse: current.lastUse + 1), at: url)
    }

    static func encode(_ wallpapers: [DisplayIdentifier: String], lastUse: Int) -> Data {
        let displays = wallpapers.sorted { $0.key < $1.key }.map {
            "\(displayPrefix)\($0.key.uuid.uuidString) \($0.value)"
        }
        return Data(([header] + displays + ["\(lastUsePrefix)\(lastUse)"]).joined(separator: "\n").utf8)
    }

    private static func decode(_ data: Data) -> (wallpapers: [DisplayIdentifier: String], lastUse: Int) {
        var wallpapers: [DisplayIdentifier: String] = [:]
        var lastUse = 0
        // Content that is not UTF-8 (a test placing an unrecognized store) decodes as an empty store.
        for line in (String(bytes: data, encoding: .utf8) ?? "").split(separator: "\n") {
            if line.hasPrefix(lastUsePrefix) {
                lastUse = Int(line.dropFirst(lastUsePrefix.count)) ?? 0
            } else if line.hasPrefix(displayPrefix) {
                let fields = line.dropFirst(displayPrefix.count).split(separator: " ", maxSplits: 1)
                if fields.count == 2, let uuid = UUID(uuidString: String(fields[0])) {
                    wallpapers[DisplayIdentifier(uuid: uuid)] = String(fields[1])
                }
            }
        }
        return (wallpapers, lastUse)
    }
}
