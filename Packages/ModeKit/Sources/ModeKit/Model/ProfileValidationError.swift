/// A rule from ``ProfileValidation`` that a profile or one of its values breaks.
///
/// Cases carry enough context for an actionable message and never contain file system paths.
public enum ProfileValidationError: Error, Equatable, Sendable {
    /// The name is empty after trimming whitespace.
    case emptyName
    /// The trimmed name has more characters than ``ProfileValidation/nameLengthRange`` allows.
    case nameTooLong(characterCount: Int)
    /// The profile contains more than one step for the same action.
    case duplicateStep(ActionIdentifier)
    /// The value is not a strict reverse-DNS bundle identifier.
    case invalidBundleIdentifier(String)
    /// A specific display selection names no display.
    case emptyDisplaySelection
    /// A wallpaper image is not given as a file URL.
    case imageNotFileURL
    /// The auto-exit time is outside ``ProfileValidation/autoExitSecondsRange``.
    case autoExitOutOfRange(seconds: Int)
}
