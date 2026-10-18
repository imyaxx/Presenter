import ModeKit
import Testing

@testable import PresenterApp

/// Runs only scripts that send no Apple event to another application and need no permission (ADR-040).
@Suite(.timeLimit(.minutes(1)))
struct NSAppleScriptRunnerTests {
    private let runner = NSAppleScriptRunner()

    @Test
    func aScriptWithAResultSucceeds() async throws {
        try await runner.run(AppleScript("return 1 + 1"), timeout: .seconds(10))
    }

    @Test
    func errorMinus1743IsNotAuthorized() async {
        await #expect(throws: AppleScriptError.notAuthorized) {
            try await runner.run(AppleScript("error number -1743"), timeout: .seconds(10))
        }
    }

    @Test
    func errorMinus1712IsTimedOut() async {
        await #expect(throws: AppleScriptError.timedOut) {
            try await runner.run(AppleScript("error number -1712"), timeout: .seconds(10))
        }
    }

    @Test
    func anyOtherErrorKeepsItsNumberAndMessage() async {
        await #expect(throws: AppleScriptError.failed(code: 42, message: "boom")) {
            try await runner.run(AppleScript("error \"boom\" number 42"), timeout: .seconds(10))
        }
    }

    @Test
    func aScriptThatDoesNotCompileFails() async {
        await #expect {
            try await runner.run(AppleScript("this is not ( AppleScript"), timeout: .seconds(10))
        } throws: { error in
            if case .failed = error as? AppleScriptError { true } else { false }
        }
    }

    @Test
    func theWatchdogFiresWhenTheScriptOutlivesTheTimeout() async {
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: AppleScriptError.timedOut) {
            try await runner.run(AppleScript("delay 2"), timeout: .milliseconds(300))
        }

        #expect(clock.now - start < .seconds(1.5))
    }

    @Test
    func aCancelledCallerGetsCancellationErrorAtOnce() async {
        let call = Task { try await runner.run(AppleScript("delay 2"), timeout: .seconds(10)) }
        try? await Task.sleep(for: .milliseconds(100))

        call.cancel()

        await #expect(throws: CancellationError.self) { try await call.value }
    }

    @Test
    func twoScriptsIssuedAtOnceDoNotOverlap() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        async let first: Void = runner.run(AppleScript("delay 0.4"), timeout: .seconds(10))
        async let second: Void = runner.run(AppleScript("delay 0.4"), timeout: .seconds(10))
        _ = try await (first, second)

        #expect(clock.now - start >= .seconds(0.8))
    }
}
