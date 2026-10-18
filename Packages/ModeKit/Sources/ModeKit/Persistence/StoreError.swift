import Foundation

/// A failure of ``ProfileStore`` or ``SessionStore``. Carries file names, never full paths.
public enum StoreError: Error, Equatable, Sendable {
    /// The file was written by a newer build. It is left untouched.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The file exists but is empty, not valid JSON, has the wrong shape, or holds invalid content.
    case corrupted(fileName: String, reason: String)
    /// A profile passed to a save breaks a rule.
    case invalidProfile(ProfileValidationError)
    /// Two profiles passed to a save share an identifier.
    case duplicateProfileID(UUID)
    /// Reading, writing or removing the file failed.
    case ioFailure(fileName: String, reason: String)
    /// The content could not be encoded as JSON.
    case encodingFailed(fileName: String, reason: String)
}
