/// Auto-hides the menu bar ("Always") through three preference keys and a distributed notification (ADR-026,
/// ADR-037, spike S1).
///
/// The three keys are always handled together, because System Settings writes all three. Work that would change
/// nothing is skipped: no write and no notification (ADR-035). Restore writes each captured value with its type, or
/// removes the key when it was absent at capture; it never writes a default for an absent key.
///
/// The notification name is undocumented and posting cannot report whether macOS reacted, so the action cannot
/// verify the live effect.
///
/// Threading: a value type holding its ports; safe to use from any context.
public struct MenuBarAction: ModeAction {
    /// The three values before activation; nil when a key was absent.
    public struct Snapshot: Codable, Equatable, Sendable {
        public let autoHideOption: DefaultsValue?
        public let hideMenuBar: DefaultsValue?
        public let visibleInFullscreen: DefaultsValue?

        public init(autoHideOption: DefaultsValue?, hideMenuBar: DefaultsValue?, visibleInFullscreen: DefaultsValue?) {
            self.autoHideOption = autoHideOption
            self.hideMenuBar = hideMenuBar
            self.visibleInFullscreen = visibleInFullscreen
        }

        /// In the order of ``MenuBarAction/keys``.
        var values: [DefaultsValue?] {
            [autoHideOption, hideMenuBar, visibleInFullscreen]
        }
    }

    /// The three values after apply: the "Always" row of the S1 table.
    public struct AppliedState: Codable, Equatable, Sendable {
        public let autoHideOption: DefaultsValue
        public let hideMenuBar: DefaultsValue
        public let visibleInFullscreen: DefaultsValue

        public init(autoHideOption: DefaultsValue, hideMenuBar: DefaultsValue, visibleInFullscreen: DefaultsValue) {
            self.autoHideOption = autoHideOption
            self.hideMenuBar = hideMenuBar
            self.visibleInFullscreen = visibleInFullscreen
        }

        /// In the order of ``MenuBarAction/keys``.
        var values: [DefaultsValue] {
            [autoHideOption, hideMenuBar, visibleInFullscreen]
        }
    }

    static let autoHideOptionKey = DefaultsKey(domain: "com.apple.controlcenter", name: "AutoHideMenuBarOption")
    static let hideMenuBarKey = DefaultsKey(domain: "NSGlobalDomain", name: "_HIHideMenuBar")
    static let visibleInFullscreenKey = DefaultsKey(domain: "NSGlobalDomain", name: "AppleMenuBarVisibleInFullscreen")
    /// The write order of apply and restore.
    static let keys = [autoHideOptionKey, hideMenuBarKey, visibleInFullscreenKey]
    static let alwaysHidden = AppliedState(
        autoHideOption: .integer(0),
        hideMenuBar: .bool(true),
        visibleInFullscreen: .bool(false),
    )

    private let defaults: any DefaultsStore
    private let notifier: any DistributedNotifier

    public var identifier: ActionIdentifier {
        .menuBar
    }

    /// Creates the action over its ports.
    public init(defaults: any DefaultsStore, notifier: any DistributedNotifier) {
        self.defaults = defaults
        self.notifier = notifier
    }

    /// Reads the three keys. Changes nothing.
    ///
    /// - Throws: ``DefaultsError``.
    public func capture() async throws -> Snapshot {
        Snapshot(
            autoHideOption: try await defaults.value(for: Self.autoHideOptionKey),
            hideMenuBar: try await defaults.value(for: Self.hideMenuBarKey),
            visibleInFullscreen: try await defaults.value(for: Self.visibleInFullscreenKey),
        )
    }

    /// Writes the "Always" row in key order and posts the notification once, unless all three already match.
    ///
    /// - Throws: ``DefaultsError``; a failing write stops the apply before the notification.
    public func apply() async throws -> AppliedState {
        let target = Self.alwaysHidden
        guard try await currentValues() != target.values else {
            return target
        }
        for (key, value) in zip(Self.keys, target.values) {
            try await defaults.set(value, for: key)
        }
        await notifier.post(.menuBarHidingChanged)
        return target
    }

    /// Returns the three keys to the snapshot and posts the notification once, unless the user changed any key since
    /// apply (skipped) or all three already equal the snapshot (nothing to do). `applied: nil` restores
    /// unconditionally.
    ///
    /// - Throws: ``DefaultsError``. A failing write or remove does not stop the other keys; the notification is still
    ///   posted, then the first error is thrown.
    public func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome {
        let current = try await currentValues()
        if let applied, current != applied.values {
            return .skippedBecauseChangedByUser
        }
        guard current != snapshot.values else {
            return .restored
        }
        var firstError: (any Error)?
        for (key, captured) in zip(Self.keys, snapshot.values) {
            do {
                try await write(captured, for: key)
            } catch {
                firstError = firstError ?? error
            }
        }
        await notifier.post(.menuBarHidingChanged)
        if let firstError {
            throw firstError
        }
        return .restored
    }

    private func currentValues() async throws -> [DefaultsValue?] {
        var values: [DefaultsValue?] = []
        for key in Self.keys {
            values.append(try await defaults.value(for: key))
        }
        return values
    }

    private func write(_ value: DefaultsValue?, for key: DefaultsKey) async throws {
        if let value {
            try await defaults.set(value, for: key)
        } else {
            try await defaults.remove(key)
        }
    }
}
