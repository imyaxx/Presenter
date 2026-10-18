import Foundation

/// Wall-clock time and sleeping for the session controller. Named `SessionClock` so it does not shadow the
/// standard library's `Clock` protocol (ADR-032).
///
/// Threading: implementations are `Sendable`.
public protocol SessionClock: Sendable {
    /// The current date, recorded as a session's start time.
    func now() -> Date

    /// Suspends for `duration`.
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled before the duration has passed.
    func sleep(for duration: Duration) async throws
}
