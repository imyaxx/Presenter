/// A failure of ``DockAction`` beyond the errors of its ports.
public enum DockActionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The script ran but `com.apple.dock autohide` did not read back as `true`; the mechanism did not take effect.
    case settingNotApplied(observed: DefaultsValue?)

    public var description: String {
        switch self {
        case .settingNotApplied(let observed):
            "Dock auto-hide was not applied; autohide reads \(observed.map { "\($0)" } ?? "absent")"
        }
    }
}
