import os

/// A value that arrives once, from any thread, and any number of async waiters.
///
/// Waiting is cancellation-aware: a cancelled waiter returns nil at once and the value stays available to others.
/// Used to bridge callback-style completion (a process's termination handler, a script finishing on its thread) to
/// async code without `DispatchQueue`.
final class CompletionSignal<Value: Sendable>: Sendable {
    private struct State: Sendable {
        var value: Value?
        var waiters: [UInt64: CheckedContinuation<Value?, Never>] = [:]
        var nextWaiterID: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Delivers the value to every current and future waiter. Only the first call has an effect.
    func complete(with value: Value) {
        let waiters = state.withLock { state -> [CheckedContinuation<Value?, Never>] in
            guard state.value == nil else {
                return []
            }
            state.value = value
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters {
            waiter.resume(returning: value)
        }
    }

    /// Returns the value once it arrives, or nil when the waiting task is cancelled.
    func wait() async -> Value? {
        let waiterID = state.withLock { state -> UInt64 in
            state.nextWaiterID += 1
            return state.nextWaiterID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediate = state.withLock { state -> Value?? in
                    if let value = state.value {
                        return .some(value)
                    }
                    if Task.isCancelled {
                        return .some(nil)
                    }
                    state.waiters[waiterID] = continuation
                    return .none
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: waiterID) }?.resume(returning: nil)
        }
    }

    /// Returns the value if it arrives within `duration`, otherwise nil. Also nil when the waiting task is cancelled.
    func wait(upTo duration: Duration) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask { await self.wait() }
            group.addTask {
                // A cancelled sleep only means the value arrived first; either way this child reports no value.
                try? await Task.sleep(for: duration)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap { $0 }
        }
    }
}
