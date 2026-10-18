import Darwin
import Foundation
import ModeKit

/// The real ``ProcessRunner``: `Process` with an absolute executable and an argv array, never a shell (ADR-040).
///
/// Standard input, output and error are the null device; the environment is a fixed minimal one. On timeout the
/// child gets SIGTERM, then SIGKILL after ``terminationGracePeriod``, and the call returns only once it has exited.
/// Cancelling the calling task stops the child the same way and throws `CancellationError`.
///
/// Threading: a value type; `run` may be called from any context and never blocks a thread while waiting.
struct FoundationProcessRunner: ProcessRunner {
    /// Time between SIGTERM and SIGKILL when a process must be stopped.
    static let terminationGracePeriod = Duration.seconds(2)
    private static let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"]

    /// - Throws: ``ProcessError/launchFailed(reason:)``, ``ProcessError/timedOut(_:)``, or `CancellationError`.
    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = Self.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exit = CompletionSignal<Int32>()
        process.terminationHandler = { exit.complete(with: $0.terminationStatus) }
        do {
            try process.run()
        } catch {
            throw ProcessError.launchFailed(reason: String(describing: error))
        }
        if let status = await exit.wait(upTo: command.timeout) {
            return ProcessResult(exitCode: status)
        }
        // SIGTERM through Process, which does nothing once the child has been reaped.
        process.terminate()
        await Self.escalate(process.processIdentifier, exit: exit)
        if Task.isCancelled {
            throw CancellationError()
        }
        throw ProcessError.timedOut(command.timeout)
    }

    /// After SIGTERM: sends SIGKILL if the process has not exited within the grace period, then waits until it has.
    ///
    /// Runs in an unstructured task on purpose: when the caller was cancelled, its own waits end at once, but the
    /// escalation and the final wait must still complete so the child never outlives the call. SIGKILL is sent only
    /// while the termination handler has not reported an exit; only the short gap between the reap and the handler
    /// could let it reach a reused process identifier.
    private static func escalate(_ processID: Int32, exit: CompletionSignal<Int32>) async {
        await Task {
            if await exit.wait(upTo: terminationGracePeriod) == nil {
                kill(processID, SIGKILL)
                _ = await exit.wait()
            }
        }.value
    }
}
