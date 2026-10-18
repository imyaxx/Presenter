import ModeKit

/// A ``DistributedNotifier`` that records posts in order.
actor FakeDistributedNotifier: DistributedNotifier {
    private(set) var posts: [DistributedNotificationName] = []

    func post(_ name: DistributedNotificationName) async {
        posts.append(name)
    }
}
