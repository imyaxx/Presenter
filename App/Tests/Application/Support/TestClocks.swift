import Foundation
import ModeKit

/// A ``SessionClock`` whose sleeps end at once, so a deadline passes immediately.
struct ImmediateClock: SessionClock {
    func now() -> Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
    }
}

/// A ``SessionClock`` whose sleeps end only when the sleeping task is cancelled, so a deadline never passes.
struct StoppedClock: SessionClock {
    func now() -> Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    func sleep(for duration: Duration) async throws {
        while !Task.isCancelled {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CancellationError()
    }
}
