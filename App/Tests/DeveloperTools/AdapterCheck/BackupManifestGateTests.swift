#if DEBUG
import Foundation
import Testing

@testable import PresenterApp

/// Uses temporary directories only.
struct BackupManifestGateTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeBackup(manifest: String?, files: [String] = []) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "presenter-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            let url = directory.appending(path: file)
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        if let manifest {
            try Data(manifest.utf8).write(to: directory.appending(path: "MANIFEST.json"))
        }
        return directory
    }

    private func manifest(createdAt: Date, version: Int = 1, files: [String] = ["keys.tsv"]) -> String {
        let date = ISO8601DateFormatter().string(from: createdAt)
        let list = files.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"formatVersion\":\(version),\"createdAt\":\"\(date)\",\"files\":[\(list)]}"
    }

    @Test
    func aFreshCompleteBackupIsAccepted() throws {
        let backup = try makeBackup(manifest: manifest(createdAt: Self.now - 3600), files: ["keys.tsv"])
        defer { try? FileManager.default.removeItem(at: backup) }

        let accepted = try BackupManifestGate.check(backup, now: Self.now)

        #expect(accepted.files == ["keys.tsv"])
    }

    @Test
    func noBackupOptionIsRefused() {
        #expect(throws: BackupGateError.missingBackupOption) { try BackupManifestGate.check(nil, now: Self.now) }
    }

    @Test
    func aDirectoryWithoutManifestIsRefused() throws {
        let backup = try makeBackup(manifest: nil)
        defer { try? FileManager.default.removeItem(at: backup) }

        #expect(throws: BackupGateError.missingManifest) { try BackupManifestGate.check(backup, now: Self.now) }
    }

    @Test
    func aMalformedManifestIsRefused() throws {
        let backup = try makeBackup(manifest: "{\"formatVersion\": 1}")
        defer { try? FileManager.default.removeItem(at: backup) }

        #expect(throws: BackupGateError.malformedManifest) { try BackupManifestGate.check(backup, now: Self.now) }
    }

    @Test
    func anUnknownFormatVersionIsRefused() throws {
        let backup = try makeBackup(manifest: manifest(createdAt: Self.now, version: 2), files: ["keys.tsv"])
        defer { try? FileManager.default.removeItem(at: backup) }

        #expect(throws: BackupGateError.unsupportedFormatVersion(2)) {
            try BackupManifestGate.check(backup, now: Self.now)
        }
    }

    @Test
    func aBackupOlderThanADayIsRefused() throws {
        let backup = try makeBackup(manifest: manifest(createdAt: Self.now - 25 * 3600), files: ["keys.tsv"])
        defer { try? FileManager.default.removeItem(at: backup) }

        #expect(throws: BackupGateError.stale(hours: 25)) { try BackupManifestGate.check(backup, now: Self.now) }
    }

    @Test
    func aBackupDatedInTheFutureIsRefused() throws {
        let backup = try makeBackup(manifest: manifest(createdAt: Self.now + 60), files: ["keys.tsv"])
        defer { try? FileManager.default.removeItem(at: backup) }

        #expect(throws: BackupGateError.createdInTheFuture) { try BackupManifestGate.check(backup, now: Self.now) }
    }

    @Test
    func aBackupMissingAListedFileIsRefused() throws {
        let listed = manifest(createdAt: Self.now, files: ["keys.tsv", "wallpaper/Index.plist"])
        let backup = try makeBackup(manifest: listed, files: ["keys.tsv"])
        defer { try? FileManager.default.removeItem(at: backup) }

        #expect(throws: BackupGateError.missingFile("wallpaper/Index.plist")) {
            try BackupManifestGate.check(backup, now: Self.now)
        }
    }
}
#endif
