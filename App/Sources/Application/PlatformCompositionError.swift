/// A failure to build ``PlatformComposition``.
enum PlatformCompositionError: Error, Equatable, Sendable {
    /// The app bundle has no bundle identifier, so no support directory or log subsystem can be named.
    case missingBundleIdentifier
    /// The user's Application Support directory could not be resolved.
    case applicationSupportUnavailable(reason: String)
}
