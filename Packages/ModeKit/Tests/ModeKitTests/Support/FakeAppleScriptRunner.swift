import ModeKit

/// An ``AppleScriptRunner`` that records scripts and returns a scripted error per script (success by default).
///
/// When given a ``FakeDefaultsStore`` it models System Events as observed in spike S4 (docs/07-macos-integration.md):
/// `set autohide of dock preferences to true` writes `.bool(true)` and `... to false` writes `.bool(false)` to
/// `com.apple.dock autohide`, always an explicit key, never a delete. Without a store it changes nothing.
actor FakeAppleScriptRunner: AppleScriptRunner {
    static let dockAutohideKey = DefaultsKey(domain: "com.apple.dock", name: "autohide")
    private static let dockPreferencesMarker = "set autohide of dock preferences to "

    private(set) var scripts: [AppleScript] = []
    private(set) var timeouts: [Duration] = []
    private var errors: [String: any Error] = [:]
    private let systemEvents: FakeDefaultsStore?

    init(systemEvents: FakeDefaultsStore? = nil) {
        self.systemEvents = systemEvents
    }

    /// Makes every run of `script` throw `error`.
    func fail(_ script: AppleScript, with error: any Error) {
        errors[script.source] = error
    }

    func run(_ script: AppleScript, timeout: Duration) async throws {
        scripts.append(script)
        timeouts.append(timeout)
        if let error = errors[script.source] {
            throw error
        }
        guard let systemEvents, let range = script.source.range(of: Self.dockPreferencesMarker) else {
            return
        }
        let enabled = script.source[range.upperBound...] == "true"
        await systemEvents.place(.bool(enabled), for: Self.dockAutohideKey)
    }
}
