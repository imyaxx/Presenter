/// Posts distributed notifications to the user's session.
///
/// Posting cannot report whether any process reacted. In-process call with no timeout by design, like
/// ``DefaultsStore``; the implementation must not block. Threading: implementations are `Sendable`.
public protocol DistributedNotifier: Sendable {
    /// Posts the notification with no object and no user info.
    func post(_ name: DistributedNotificationName) async
}
