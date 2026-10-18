import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Tests ``DistributedNotificationCenterNotifier``. Posts only a private notification name of this test's own, never
/// the menu bar notification (ADR-040).
@Suite(.timeLimit(.minutes(1)))
struct DistributedNotifierTests {
    @Test
    func aPostedNameReachesAnObserverOfThatName() async {
        let name = DistributedNotificationName(rawValue: "dev.imyaxx.presenter.tests.notification.\(UUID().uuidString)")
        let received = CompletionSignal<String>()
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(forName: Notification.Name(name.rawValue), object: nil, queue: nil) {
            received.complete(with: $0.name.rawValue)
        }
        defer { center.removeObserver(observer) }

        await DistributedNotificationCenterNotifier().post(name)

        #expect(await received.wait(upTo: .seconds(5)) == name.rawValue)
    }
}
