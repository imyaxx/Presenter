import ModeKit

/// Restores an active session before the app quits, within ``restoreDeadline`` (ADR-043).
///
/// A restore still running at the deadline, or one that left actions unrestored, still lets the app quit:
/// `session.json` persists and the next launch recovers (ADR-008). Other states quit at once for the same reason.
/// How macOS treats this wait at logout and shutdown is unverified.
@MainActor
final class QuitCoordinator {
    enum Outcome: Equatable, Sendable {
        /// No session was active.
        case nothingToRestore
        case restored
        /// Some actions could not be restored; `session.json` keeps them.
        case restoredWithFailures
        /// The restore did not finish in time; it may still finish before the process ends.
        case deadlineReached
    }

    static let restoreDeadline = Duration.seconds(15)

    private let session: any SessionControlling
    private let clock: any SessionClock
    private let deadline: Duration
    private var restore: Task<Void, Never>?

    init(session: any SessionControlling, clock: any SessionClock, deadline: Duration = restoreDeadline) {
        self.session = session
        self.clock = clock
        self.deadline = deadline
    }

    func prepareToQuit() async -> Outcome {
        guard case .active = await session.state else {
            return .nothingToRestore
        }
        let finished = CompletionSignal<Outcome>()
        // Unstructured on purpose: the restore must keep going when the wait gives up at the deadline.
        restore = Task { [session] in
            finished.complete(with: await Self.deactivate(session))
        }
        return await withTaskGroup(of: Outcome?.self) { [clock, deadline] group in
            group.addTask { await finished.wait() }
            group.addTask {
                // A cancelled sleep means the restore finished first; this child's result is then not used.
                try? await clock.sleep(for: deadline)
                return .deadlineReached
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap { $0 } ?? .deadlineReached
        }
    }

    private nonisolated static func deactivate(_ session: any SessionControlling) async -> Outcome {
        do {
            guard case .performed(let report) = try await session.deactivate() else {
                return .nothingToRestore
            }
            return report.failed.isEmpty ? .restored : .restoredWithFailures
        } catch {
            return .restoredWithFailures
        }
    }
}
