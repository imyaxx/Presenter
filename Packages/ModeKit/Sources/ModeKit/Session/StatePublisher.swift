import Foundation

/// Delivers state changes to every ``SessionController/stateUpdates()`` subscriber. Owned by the controller actor.
final class StatePublisher {
    private var continuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]

    func subscribe(startingWith state: SessionState) -> AsyncStream<SessionState> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionState.self)
        continuation.yield(state)
        continuations[UUID()] = continuation
        return stream
    }

    func publish(_ state: SessionState) {
        var terminated: [UUID] = []
        for (id, continuation) in continuations {
            if case .terminated = continuation.yield(state) {
                terminated.append(id)
            }
        }
        for id in terminated {
            continuations[id] = nil
        }
    }
}
