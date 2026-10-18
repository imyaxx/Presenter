import Foundation
import ModeKit

/// The real ``AppleScriptRunner``: `NSAppleScript` on one dedicated background thread (ADR-040).
///
/// Scripts run one at a time on an ``AppleScriptThread``, never on the main thread. `timeout` is a watchdog: when
/// the script has not finished in time the call throws ``AppleScriptError/timedOut`` and the late result is
/// discarded. The script itself cannot be stopped and keeps the thread busy until it ends; the system's own -1712
/// arrives after 120 s of an unanswered Automation prompt (S4). Whether `NSAppleScript` behaves the same off the main
/// thread when it sends Apple events to System Events is unverified (docs/07).
///
/// Threading: `run` may be called from any context; a cancelled caller gets `CancellationError` at once while the
/// script finishes on its thread.
final class NSAppleScriptRunner: AppleScriptRunner {
    /// Reported when the system gives an error without an error number.
    static let missingErrorCode = 0

    private let thread = AppleScriptThread()

    deinit {
        thread.stop()
    }

    /// - Throws: ``AppleScriptError`` mapped from the script's error number and message, ``AppleScriptError/timedOut``
    ///   from the watchdog, or `CancellationError`.
    func run(_ script: AppleScript, timeout: Duration) async throws {
        let completion = CompletionSignal<Result<Void, AppleScriptError>>()
        let source = script.source
        thread.submit { completion.complete(with: Self.execute(source)) }
        guard let result = await completion.wait(upTo: timeout) else {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw AppleScriptError.timedOut
        }
        try result.get()
    }

    /// Runs the source on the calling thread and maps the error dictionary of `NSAppleScript`.
    private static func execute(_ source: String) -> Result<Void, AppleScriptError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.failed(code: missingErrorCode, message: "The script could not be created"))
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else {
            return .success(())
        }
        let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? missingErrorCode
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? ""
        return .failure(AppleScriptError(code: code, message: message))
    }
}
