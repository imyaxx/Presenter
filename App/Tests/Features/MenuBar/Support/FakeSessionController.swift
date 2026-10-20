import Foundation
import ModeKit

@testable import PresenterApp

/// A scripted ``SessionControlling`` for the menu bar tests. Records every trigger; `emit` pushes a state to every
/// subscriber; an optional gate holds `activate` and `deactivate` until it is opened.
actor FakeSessionController: SessionControlling {
    private(set) var state: SessionState
    private(set) var calls: [String] = []
    private var continuations: [AsyncStream<SessionState>.Continuation] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var isGated = false

    private var recoveryOutcome = RecoveryOutcome.nothingToRecover
    private var activation: Result<TriggerResult<ActiveSession>, SessionError> = .success(.ignored(currentState: .idle))
    private var deactivation: Result<TriggerResult<RestoreReport>, SessionError> = .success(
        .ignored(currentState: .idle))
    private var retry = TriggerResult<RecoveryOutcome>.ignored(currentState: .idle)
    private var discard: Result<TriggerResult<Void>, SessionError> = .success(.performed(()))

    init(state: SessionState = .idle) {
        self.state = state
    }

    func setRecoveryOutcome(_ outcome: RecoveryOutcome) { recoveryOutcome = outcome }
    func setActivation(_ result: Result<TriggerResult<ActiveSession>, SessionError>) { activation = result }
    func setDeactivation(_ result: Result<TriggerResult<RestoreReport>, SessionError>) { deactivation = result }
    func setRetry(_ result: TriggerResult<RecoveryOutcome>) { retry = result }
    func setDiscard(_ result: Result<TriggerResult<Void>, SessionError>) { discard = result }

    /// Holds the next `activate` or `deactivate` until ``openGate()``.
    func closeGate() { isGated = true }

    func openGate() {
        isGated = false
        gate?.resume()
        gate = nil
    }

    func emit(_ newState: SessionState) {
        state = newState
        for continuation in continuations {
            continuation.yield(newState)
        }
    }

    func finishUpdates() {
        for continuation in continuations {
            continuation.finish()
        }
    }

    func stateUpdates() async -> AsyncStream<SessionState> {
        let (stream, continuation) = AsyncStream<SessionState>.makeStream()
        continuation.yield(state)
        continuations.append(continuation)
        return stream
    }

    func recoverIfNeeded() async -> RecoveryOutcome {
        calls.append("recover")
        return recoveryOutcome
    }

    func activate(_ profile: Profile) async throws(SessionError) -> TriggerResult<ActiveSession> {
        calls.append("activate \(profile.name)")
        await waitAtGate()
        return try activation.get()
    }

    func deactivate() async throws(SessionError) -> TriggerResult<RestoreReport> {
        calls.append("deactivate")
        await waitAtGate()
        return try deactivation.get()
    }

    func retryRestore() async -> TriggerResult<RecoveryOutcome> {
        calls.append("retry")
        return retry
    }

    func discardUnreadableSession() async throws(SessionError) -> TriggerResult<Void> {
        calls.append("discard")
        return try discard.get()
    }

    private func waitAtGate() async {
        guard isGated else {
            return
        }
        await withCheckedContinuation { gate = $0 }
    }
}
