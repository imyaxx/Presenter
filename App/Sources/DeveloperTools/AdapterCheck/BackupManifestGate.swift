#if DEBUG
import Foundation

/// Lets a command that changes the system run only with a backup made by `Scripts/adapter-check-backup.sh` less than
/// ``maximumAge`` ago, whose manifest lists files that exist (ADR-042).
enum BackupManifestGate {
    struct Manifest: Decodable, Equatable, Sendable {
        let formatVersion: Int
        let createdAt: Date
        let files: [String]
    }

    static let supportedFormatVersion = 1
    static let maximumAge: Duration = .seconds(24 * 60 * 60)
    static let manifestName = "MANIFEST.json"

    /// - Throws: ``BackupGateError``.
    static func check(_ backupDirectory: URL?, now: Date) throws(BackupGateError) -> Manifest {
        guard let backupDirectory else {
            throw BackupGateError.missingBackupOption
        }
        let manifestURL = backupDirectory.appending(path: manifestName)
        guard let data = FileManager.default.contents(atPath: manifestURL.path(percentEncoded: false)) else {
            throw BackupGateError.missingManifest
        }
        let manifest: Manifest
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(Manifest.self, from: data)
        } catch {
            throw BackupGateError.malformedManifest
        }
        guard manifest.formatVersion == supportedFormatVersion else {
            throw BackupGateError.unsupportedFormatVersion(manifest.formatVersion)
        }
        let age = now.timeIntervalSince(manifest.createdAt)
        guard age >= 0 else {
            throw BackupGateError.createdInTheFuture
        }
        guard age < TimeInterval(maximumAge.components.seconds) else {
            throw BackupGateError.stale(hours: Int(age / 3600))
        }
        let missing = manifest.files.first { file in
            !FileManager.default.fileExists(atPath: backupDirectory.appending(path: file).path(percentEncoded: false))
        }
        if let missing {
            throw BackupGateError.missingFile(missing)
        }
        return manifest
    }
}

/// Why a command that changes the system refused to run. Nothing was changed.
enum BackupGateError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingBackupOption
    case missingManifest
    case malformedManifest
    case unsupportedFormatVersion(Int)
    case createdInTheFuture
    case stale(hours: Int)
    case missingFile(String)

    var description: String {
        switch self {
        case .missingBackupOption:
            "this command changes the system: pass --backup <dir> from adapter-check-backup.sh"
        case .missingManifest: "the backup has no MANIFEST.json"
        case .malformedManifest: "MANIFEST.json cannot be read"
        case .unsupportedFormatVersion(let version): "MANIFEST.json format \(version) is not supported"
        case .createdInTheFuture: "MANIFEST.json is dated in the future"
        case .stale(let hours): "the backup is \(hours) hours old; take a new one (limit 24 hours)"
        case .missingFile(let file): "the backup lacks \(file)"
        }
    }
}
#endif
