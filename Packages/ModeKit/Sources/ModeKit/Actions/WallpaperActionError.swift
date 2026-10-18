/// A failure of ``WallpaperAction`` or ``WallpaperRestorer`` beyond the errors of their ports.
public enum WallpaperActionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The wallpaper store file does not exist.
    case storeUnavailable
    /// The desktop image was set, but the wallpaper store did not change within the polling window. Also the result
    /// when the target wallpaper already is the current one (ADR-038).
    case storeDidNotChange
    /// `killall WallpaperAgent` exited with a code other than 0 or 1.
    case wallpaperAgentRestartFailed(exitCode: Int32)

    public var description: String {
        switch self {
        case .storeUnavailable: "The wallpaper store file does not exist"
        case .storeDidNotChange: "The wallpaper store did not change after the desktop image was set"
        case .wallpaperAgentRestartFailed(let exitCode): "killall WallpaperAgent exited with \(exitCode)"
        }
    }
}
