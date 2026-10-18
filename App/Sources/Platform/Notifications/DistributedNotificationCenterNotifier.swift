import Foundation
import ModeKit

/// The real ``DistributedNotifier``: `DistributedNotificationCenter.default()`, no object, no user info, delivered
/// immediately, as the S1 throwaway app posted the menu bar notification (ADR-026).
///
/// Threading: a value type; posting does not wait for observers.
struct DistributedNotificationCenterNotifier: DistributedNotifier {
    func post(_ name: DistributedNotificationName) async {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(name.rawValue),
            object: nil,
            userInfo: nil,
            deliverImmediately: true,
        )
    }
}
