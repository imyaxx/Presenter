/// Identifies the system action a profile step drives and a session record restores.
///
/// Persisted as its raw string value, for example `"dock"`.
public enum ActionIdentifier: String, CaseIterable, Codable, Hashable, Sendable {
    case desktopIcons
    case dock
    case menuBar
    case hideApps
    case wallpaper
}
