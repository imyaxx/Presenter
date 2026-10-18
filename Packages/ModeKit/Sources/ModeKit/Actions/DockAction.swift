/// Auto-hides the Dock through System Events (ADR-025, spike S4) and restores the `autohide` key exactly.
///
/// `capture` reads the key only and never runs AppleScript, so it can never raise the Automation prompt. System Events
/// writes an explicit `true` or `false`; when the key was absent at capture, restore removes it after the script.
/// There is no `killall Dock` fallback. Work that would change nothing is skipped (ADR-035).
///
/// The script timeout is 130 s, above the system's 120 s limit for an unanswered permission prompt (S4), so the
/// adapter reports the system's ``AppleScriptError/timedOut``. While the first-run prompt is unanswered a session
/// stays in `applying` for up to about two minutes; onboarding requests the permission ahead of time.
///
/// Threading: a value type holding its ports; safe to use from any context.
public struct DockAction: ModeAction {
    /// The value of `autohide` before activation; nil when the key was absent.
    public struct Snapshot: Codable, Equatable, Sendable {
        public let autohide: DefaultsValue?

        public init(autohide: DefaultsValue?) {
            self.autohide = autohide
        }
    }

    /// The value of `autohide` read back after apply.
    public struct AppliedState: Codable, Equatable, Sendable {
        public let autohide: DefaultsValue

        public init(autohide: DefaultsValue) {
            self.autohide = autohide
        }
    }

    static let autohideKey = DefaultsKey(domain: "com.apple.dock", name: "autohide")
    static let autohideOn = DefaultsValue.bool(true)
    static let enableAutohide = AppleScript(
        "tell application \"System Events\" to set autohide of dock preferences to true"
    )
    static let disableAutohide = AppleScript(
        "tell application \"System Events\" to set autohide of dock preferences to false"
    )
    static let scriptTimeout = Duration.seconds(130)

    private let defaults: any DefaultsStore
    private let appleScriptRunner: any AppleScriptRunner

    public var identifier: ActionIdentifier {
        .dock
    }

    /// Creates the action over its ports.
    public init(defaults: any DefaultsStore, appleScriptRunner: any AppleScriptRunner) {
        self.defaults = defaults
        self.appleScriptRunner = appleScriptRunner
    }

    /// Reads `autohide`. Changes nothing and runs no script.
    ///
    /// - Throws: ``DefaultsError``.
    public func capture() async throws -> Snapshot {
        Snapshot(autohide: try await defaults.value(for: Self.autohideKey))
    }

    /// Turns auto-hide on through System Events and reads the key back, unless it is already `true`.
    ///
    /// - Throws: ``AppleScriptError`` (for example ``AppleScriptError/notAuthorized``), ``DefaultsError``, or
    ///   ``DockActionError/settingNotApplied(observed:)`` when the key does not read back as `true`.
    public func apply() async throws -> AppliedState {
        let current = try await defaults.value(for: Self.autohideKey)
        guard current != Self.autohideOn else {
            return AppliedState(autohide: Self.autohideOn)
        }
        try await appleScriptRunner.run(Self.enableAutohide, timeout: Self.scriptTimeout)
        let readBack = try await defaults.value(for: Self.autohideKey)
        guard readBack == Self.autohideOn, let readBack else {
            throw DockActionError.settingNotApplied(observed: readBack)
        }
        return AppliedState(autohide: readBack)
    }

    /// Returns auto-hide to the snapshot's state through System Events when needed, then makes the key equal to the
    /// snapshot exactly (removing it when it was absent at capture). Skipped when the user changed the value since
    /// apply. `applied: nil` restores unconditionally.
    ///
    /// - Throws: ``AppleScriptError`` or ``DefaultsError``.
    public func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome {
        var current = try await defaults.value(for: Self.autohideKey)
        if let applied, current != applied.autohide {
            return .skippedBecauseChangedByUser
        }
        let targetIsOn = snapshot.autohide == Self.autohideOn
        if (current == Self.autohideOn) != targetIsOn {
            let script = targetIsOn ? Self.enableAutohide : Self.disableAutohide
            try await appleScriptRunner.run(script, timeout: Self.scriptTimeout)
            current = try await defaults.value(for: Self.autohideKey)
        }
        if let captured = snapshot.autohide {
            if current != captured {
                try await defaults.set(captured, for: Self.autohideKey)
            }
        } else if current != nil {
            try await defaults.remove(Self.autohideKey)
        }
        return .restored
    }
}
