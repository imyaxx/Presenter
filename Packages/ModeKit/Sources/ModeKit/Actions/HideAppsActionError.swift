/// A failure of ``HideAppsAction`` or ``HideAppsRestorer``.
public enum HideAppsActionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// These running, hidden applications refused to unhide; the others were unhidden.
    case couldNotUnhide([BundleIdentifier])

    public var description: String {
        switch self {
        case .couldNotUnhide(let applications):
            "Applications refused to unhide: \(applications.map(\.rawValue).joined(separator: ", "))"
        }
    }
}
