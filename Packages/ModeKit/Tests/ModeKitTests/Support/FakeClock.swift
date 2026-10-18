import Foundation
import ModeKit

/// A ``SessionClock`` that only moves when the test calls ``advance(by:)``, or, in ``SleepMode/immediate`` mode, by
/// exactly the requested duration inside every `sleep`. No real time passes. Every requested sleep is recorded.
final class FakeClock: SessionClock, @unchecked Sendable {
    enum SleepMode: Sendable {
        /// A sleep ends when ``advance(by:)`` passes its deadline.
        case untilAdvanced
        /// A sleep advances the clock by its duration and returns at once, unless the task is cancelled.
        case immediate
    }

    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    // ModeKit sources use no locks; this test fake does, because `now()` is synchronous. `lock` guards every var.
    private let lock = NSLock()
    private let sleepMode: SleepMode
    private var currentDate: Date
    private var requestedSleeps: [Duration] = []
    private var elapsed = Duration.zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var sleeperWaiters: [CheckedContinuation<Void, Never>] = []

    init(now: Date = Date(timeIntervalSince1970: 1_792_238_400), sleeping sleepMode: SleepMode = .untilAdvanced) {
        currentDate = now
        self.sleepMode = sleepMode
    }

    /// Every duration passed to `sleep`, in order.
    var sleeps: [Duration] {
        lock.withLock { requestedSleeps }
    }

    var sleeperCount: Int {
        lock.withLock { sleepers.count }
    }

    func now() -> Date {
        lock.withLock { currentDate }
    }

    func sleep(for duration: Duration) async throws {
        lock.withLock { requestedSleeps.append(duration) }
        if sleepMode == .immediate {
            try Task.checkCancellation()
            lock.withLock { elapsed += duration }
            return
        }
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
