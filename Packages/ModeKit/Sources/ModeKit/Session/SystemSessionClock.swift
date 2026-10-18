import Foundation

/// The real ``SessionClock``: `Date()` for the current date and `ContinuousClock` for sleeping.
///
/// Whether `ContinuousClock` keeps counting while the Mac sleeps, and so whether an auto-exit can fire right after
/// wake, is unverified on the target macOS versions.
public struct SystemSessionClock: SessionClock {
    /// Creates the system clock.
    public init() {}

    public func now() -> Date {
        Date()
    }

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
