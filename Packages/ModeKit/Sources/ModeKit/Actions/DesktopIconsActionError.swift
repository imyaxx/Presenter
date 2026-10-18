/// A failure of ``DesktopIconsAction`` beyond the errors of its ports.
public enum DesktopIconsActionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// `killall Finder` exited with a code other than 0 or 1.
    case finderRestartFailed(exitCode: Int32)

    public var description: String {
        switch self {
        case .finderRestartFailed(let exitCode): "killall Finder exited with \(exitCode)"
        }
    }
}
