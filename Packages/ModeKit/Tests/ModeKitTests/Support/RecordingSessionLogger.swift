import Foundation
import ModeKit

/// A ``SessionLogger`` that keeps every event in order.
final class RecordingSessionLogger: SessionLogger, @unchecked Sendable {
    // ModeKit sources use no locks; this test fake does, because `log` is synchronous. `lock` guards `recorded`.
    private let lock = NSLock()
    private var recorded: [SessionEvent] = []

    var events: [SessionEvent] {
        lock.withLock { recorded }
    }

    func log(_ event: SessionEvent) {
        lock.withLock { recorded.append(event) }
    }
}
