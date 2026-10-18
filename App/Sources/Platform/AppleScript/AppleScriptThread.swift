import Foundation

/// One dedicated background thread that runs submitted jobs one at a time, in submission order (ADR-040).
///
/// `NSAppleScript` calls block until the script ends, for example for up to 120 s while an Automation prompt is
/// unanswered, and cannot be cancelled. Running them here keeps the main thread and the cooperative thread pool free,
/// and guarantees that two scripts never run at the same time. Uses a `Thread` and `NSCondition`, not
/// `DispatchQueue` (docs/03).
final class AppleScriptThread: @unchecked Sendable {
    // Unchecked: `condition` guards `pendingJobs` and `isStopping`, which are only touched while it is locked.
    private let condition = NSCondition()
    private var pendingJobs: [@Sendable () -> Void] = []
    private var isStopping = false

    /// Starts the thread. It runs until ``stop()`` and the jobs submitted before it have finished.
    init() {
        let thread = Thread { [self] in runJobs() }
        thread.name = "Presenter AppleScript"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Queues `job` to run after every job submitted before it.
    func submit(_ job: @escaping @Sendable () -> Void) {
        condition.lock()
        pendingJobs.append(job)
        condition.signal()
        condition.unlock()
    }

    /// Lets the thread exit once the queued jobs have run.
    func stop() {
        condition.lock()
        isStopping = true
        condition.signal()
        condition.unlock()
    }

    private func runJobs() {
        while let job = nextJob() {
            autoreleasepool { job() }
        }
    }

    private func nextJob() -> (@Sendable () -> Void)? {
        condition.lock()
        defer { condition.unlock() }
        while pendingJobs.isEmpty, !isStopping {
            condition.wait()
        }
        return pendingJobs.isEmpty ? nil : pendingJobs.removeFirst()
    }
}
