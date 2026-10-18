import Foundation
import ModeKit

/// A ``WallpaperStoreInspector`` for ``FakeWallpaperStore`` content: the fingerprint is every line except the volatile
/// `lastUse` line. Data without the fake's header is rejected, as an unknown format would be. A scripted failure makes
/// every call throw.
struct FakeWallpaperStoreInspector: WallpaperStoreInspector {
    private let failure: WallpaperStoreError?

    init(failure: WallpaperStoreError? = nil) {
        self.failure = failure
    }

    func fingerprint(of store: Data) throws -> WallpaperStoreFingerprint {
        if let failure {
            throw failure
        }
        guard let text = String(bytes: store, encoding: .utf8) else {
            throw WallpaperStoreError.unrecognizedFormat(reason: "not UTF-8")
        }
        let lines = text.split(separator: "\n")
        guard lines.first == Substring(FakeWallpaperStore.header) else {
            throw WallpaperStoreError.unrecognizedFormat(reason: "missing header")
        }
        let stable = lines.filter { !$0.hasPrefix("lastUse ") }.joined(separator: "\n")
        return WallpaperStoreFingerprint(data: Data(stable.utf8))
    }
}
