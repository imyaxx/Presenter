import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Runs only harmless commands: true, false, test, sleep and a shell loop that ignores SIGTERM (ADR-040).
@Suite(.timeLimit(.minutes(1)))
struct FoundationProcessRunnerTests {
    private let runner = FoundationProcessRunner()

    private func command(
        _ path: String,
        _ arguments: [String] = [],
        timeout: Duration = .seconds(10),
    ) -> ProcessCommand {
        ProcessCommand(executableURL: URL(filePath: path), arguments: arguments, timeout: timeout)
    }

    @Test
    func exitZeroIsReturned() async throws {
        #expect(try await runner.run(command("/usr/bin/true")) == ProcessResult(exitCode: 0))
    }

    @Test
    func aNonzeroExitIsAResultNotAnError() async throws {
        #expect(try await runner.run(command("/usr/bin/false")) == ProcessResult(exitCode: 1))
    }

    @Test
    func aMissingExecutableFailsToLaunch() async {
        await #expect {
            try await runner.run(command("/usr/bin/presenter-no-such-tool"))
        } throws: { error in
            if case .launchFailed = error as? ProcessError { true } else { false }
        }
    }

    @Test
    func argumentsWithSpacesAndQuotesArePassedVerbatim() async throws {
        let tricky = "it's \"quoted\"  with  spaces; $HOME *"

        #expect(try await runner.run(command("/bin/test", [tricky, "=", tricky])).exitCode == 0)
        #expect(try await runner.run(command("/bin/test", [tricky, "=", "it's"])).exitCode == 1)
    }

    @Test
    func aCommandThatExceedsItsTimeoutIsTerminatedAndGone() async throws {
        let sleep = command("/bin/sleep", ["987.125"], timeout: .milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: ProcessError.timedOut(.milliseconds(300))) { try await runner.run(sleep) }

        #expect(clock.now - start < .seconds(2))
        #expect(try await !ProcessTableProbe.isRunning(commandLine: "/bin/sleep 987.125"))
    }

    @Test
    func aCommandThatIgnoresSIGTERMIsKilledAfterTheGracePeriod() async throws {
        let script = "trap '' TERM; while :; do :; done; echo 986"
        let stubborn = command("/bin/sh", ["-c", script], timeout: .milliseconds(200))
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: ProcessError.timedOut(.milliseconds(200))) { try await runner.run(stubborn) }

        #expect(clock.now - start >= FoundationProcessRunner.terminationGracePeriod)
        #expect(try await !ProcessTableProbe.isRunning(commandLine: "/bin/sh -c \(script)"))
    }

    @Test
    func cancellingTheCallerStopsTheChild() async throws {
        let sleep = command("/bin/sleep", ["985.25"], timeout: .seconds(60))
        let call = Task { try await runner.run(sleep) }
        try await Task.sleep(for: .milliseconds(300))

        call.cancel()

        await #expect(throws: CancellationError.self) { try await call.value }
        #expect(try await !ProcessTableProbe.isRunning(commandLine: "/bin/sleep 985.25"))
    }
}
