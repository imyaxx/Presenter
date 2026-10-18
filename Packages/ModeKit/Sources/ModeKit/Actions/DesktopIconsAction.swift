import Foundation

/// Hides the desktop icons through Finder's `CreateDesktop` preference and a Finder restart (ADR-028, spike S5).
///
/// Skips work that would change nothing: no write and no Finder restart when the value already equals the target
/// (ADR-035). Restore writes the captured value with its type, or removes the key when it was absent at capture;
/// it never writes a default for an absent key.
///
/// Threading: a value type holding its ports; safe to use from any context.
public struct DesktopIconsAction: ModeAction {
    /// The value of `CreateDesktop` before activation; nil when the key was absent.
    public struct Snapshot: Codable, Equatable, Sendable {
        public let createDesktop: DefaultsValue?

        public init(createDesktop: DefaultsValue?) {
            self.createDesktop = createDesktop
        }
    }

    /// The value of `CreateDesktop` after apply.
    public struct AppliedState: Codable, Equatable, Sendable {
        public let createDesktop: DefaultsValue

        public init(createDesktop: DefaultsValue) {
            self.createDesktop = createDesktop
        }
    }

    static let createDesktopKey = DefaultsKey(domain: "com.apple.finder", name: "CreateDesktop")
    static let iconsHidden = DefaultsValue.bool(false)
    static let restartFinder = ProcessCommand(
        executableURL: URL(filePath: "/usr/bin/killall"),
        arguments: ["Finder"],
        timeout: .seconds(10),
    )

    private static let signalledExitCode: Int32 = 0
    // man killall (macOS 27.0): "The killall utility exits 0 if some processes have been found and signalled
    // successfully. Otherwise, a status of 1 will be returned." Exit 1 is treated as success: when Finder is not
    // running there is nothing to restart and launchd brings it back with the new preference. The same code also
    // covers a Finder that was found but not signalled; the preference is written either way and applies at
    // Finder's next launch. Exit 1 has not been observed on a running system (docs/07-macos-integration.md).
    private static let notSignalledExitCode: Int32 = 1

    private let defaults: any DefaultsStore
    private let processRunner: any ProcessRunner

    public var identifier: ActionIdentifier {
        .desktopIcons
    }

    /// Creates the action over its ports.
    public init(defaults: any DefaultsStore, processRunner: any ProcessRunner) {
        self.defaults = defaults
        self.processRunner = processRunner
    }

    /// Reads `CreateDesktop`. Changes nothing.
    ///
    /// - Throws: ``DefaultsError``.
    public func capture() async throws -> Snapshot {
        Snapshot(createDesktop: try await defaults.value(for: Self.createDesktopKey))
    }

    /// Writes `CreateDesktop = false` and restarts Finder, unless the value is already `false`.
    ///
    /// - Throws: ``DefaultsError``, ``ProcessError`` or ``DesktopIconsActionError``.
    public func apply() async throws -> AppliedState {
        let current = try await defaults.value(for: Self.createDesktopKey)
        guard current != Self.iconsHidden else {
            return AppliedState(createDesktop: Self.iconsHidden)
        }
        try await defaults.set(Self.iconsHidden, for: Self.createDesktopKey)
        try await restartFinder()
        return AppliedState(createDesktop: Self.iconsHidden)
    }

    /// Returns `CreateDesktop` to the snapshot and restarts Finder, unless the user changed the value since apply
    /// (skipped) or it already equals the snapshot (nothing to do). `applied: nil` restores unconditionally.
    ///
    /// - Throws: ``DefaultsError``, ``ProcessError`` or ``DesktopIconsActionError``.
    public func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome {
        let current = try await defaults.value(for: Self.createDesktopKey)
        if let applied, current != applied.createDesktop {
            return .skippedBecauseChangedByUser
        }
        guard current != snapshot.createDesktop else {
            return .restored
        }
        if let captured = snapshot.createDesktop {
            try await defaults.set(captured, for: Self.createDesktopKey)
        } else {
            try await defaults.remove(Self.createDesktopKey)
        }
        try await restartFinder()
        return .restored
    }

    private func restartFinder() async throws {
        let result = try await processRunner.run(Self.restartFinder)
        guard result.exitCode == Self.signalledExitCode || result.exitCode == Self.notSignalledExitCode else {
            throw DesktopIconsActionError.finderRestartFailed(exitCode: result.exitCode)
        }
    }
}
