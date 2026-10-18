import Foundation
import ModeKit

/// A ``SessionClock`` that only moves when the test calls ``advance(by:)``. No real time passes.
final class FakeClock: SessionClock, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    // ModeKit sources use no locks; this test fake does, because `now()` is synchronous. `lock` guards every var.
    private let lock = NSLock()
    private var currentDate: Date
    private var elapsed = Duration.zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var sleeperWaiters: [CheckedContinuation<Void, Never>] = []

    init(now: Date = Date(timeIntervalSince1970: 1_792_238_400)) {
        currentDate = now
    }

    var sleeperCount: Int {
        lock.withLock { sleepers.count }
    }

    func now() -> Date {
        lock.withLock { currentDate }
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let waiters = lock.withLock {
                    sleepers[id] = Sleeper(deadline: elapsed + duration, continuation: continuation)
                    defer { sleeperWaiters = [] }
                    return sleeperWaiters
                }
                for waiter in waiters {
                    waiter.resume()
                }
                if Task.isCancelled {
                    lock.withLock { sleepers.removeValue(forKey: id) }?.continuation.resume(
                        throwing: CancellationError())
                }
            }
        } onCancel: {
            lock.withLock { sleepers.removeValue(forKey: id) }?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Returns once at least one task is sleeping on this clock.
    func waitForSleeper() async {
        await withCheckedContinuation { continuation in
            let isSleeping = lock.withLock {
                if sleepers.isEmpty {
                    sleeperWaiters.append(continuation)
                }
                return !sleepers.isEmpty
            }
            if isSleeping {
                continuation.resume()
            }
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has passed.
    func advance(by duration: Duration) {
        let due = lock.withLock {
            elapsed += duration
            currentDate += TimeInterval(duration.components.seconds)
            let dueSleepers = sleepers.filter { $0.value.deadline <= elapsed }
            for key in dueSleepers.keys {
                sleepers.removeValue(forKey: key)
            }
            return dueSleepers.values.map(\.continuation)
        }
        for continuation in due {
            continuation.resume()
        }
    }
}
