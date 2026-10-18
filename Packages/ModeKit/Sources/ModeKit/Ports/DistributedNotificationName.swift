/// The name of a notification posted to every process of the user's session.
public struct DistributedNotificationName: Hashable, Sendable {
    /// Tells the system to re-read the menu bar auto-hide preferences (spike S1, ADR-026). Undocumented by Apple.
    public static let menuBarHidingChanged = DistributedNotificationName(
        rawValue: "AppleInterfaceMenuBarHidingChangedNotification"
    )

    /// The notification name.
    public let rawValue: String

    /// Creates a notification name.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
