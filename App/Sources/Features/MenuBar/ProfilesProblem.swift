import ModeKit

/// Why the profile list could not be loaded. The file is never overwritten by the menu bar.
enum ProfilesProblem: Equatable, Sendable {
    case corrupted
    case newerVersion
    case unreadable

    init(_ error: any Error) {
        guard let storeError = error as? StoreError else {
            self = .unreadable
            return
        }
        switch storeError {
        case .corrupted, .invalidProfile, .duplicateProfileID: self = .corrupted
        case .unsupportedSchemaVersion: self = .newerVersion
        case .ioFailure, .encodingFailed: self = .unreadable
        }
    }
}
