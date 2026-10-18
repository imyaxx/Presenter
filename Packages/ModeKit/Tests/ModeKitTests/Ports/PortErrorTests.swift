import Foundation
import ModeKit
import Testing

struct PortErrorTests {
    @Test(arguments: [
        (-1743, AppleScriptError.notAuthorized),
        (-1712, .timedOut),
        (-1728, .failed(code: -1728, message: "Can’t get dock preferences.")),
    ])
    func appleScriptErrorMapsSystemCodes(code: Int, expected: AppleScriptError) {
        #expect(AppleScriptError(code: code, message: "Can’t get dock preferences.") == expected)
    }

    @Test
    func diagnosticsNameTheCause() {
        let key = DefaultsKey(domain: "com.apple.dock", name: "autohide")

        #expect(AppleScriptError.notAuthorized.description.contains("-1743"))
        #expect(AppleScriptError.timedOut.description.contains("-1712"))
        #expect(AppleScriptError.failed(code: -10, message: "boom").description == "AppleScript error -10: boom")
        #expect(
            DefaultsError.unsupportedValueType(key).description == "Unsupported value type for com.apple.dock autohide")
        #expect(DefaultsError.failed(reason: "denied").description.contains("denied"))
        #expect(ProcessError.timedOut(.seconds(10)).description.contains("10"))
        #expect(ProcessError.launchFailed(reason: "missing").description.contains("missing"))
    }

    @Test
    func appleScriptKeepsTheLiteralSource() {
        let script = AppleScript("tell application \"System Events\" to get autohide of dock preferences")

        #expect(script.source == #"tell application "System Events" to get autohide of dock preferences"#)
    }
}
