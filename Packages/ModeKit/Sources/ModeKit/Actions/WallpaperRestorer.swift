import Foundation

/// Puts back the wallpaper store captured by ``WallpaperAction`` and restarts the wallpaper agent (ADR-027, ADR-038).
/// Needs no profile, so crash recovery builds it from the action identifier alone.
///
/// The restore is whole-file: it also drops store entries for Spaces created during the session and reverts wallpaper
/// changes on displays or Spaces this app did not touch. The conditional check covers only what this app changed.
/// An original image file deleted during the session is not recreated. The `NSWorkspace` getters are never used.
///
/// Threading: a value type holding its ports; safe to use from any context.
public struct WallpaperRestorer: ActionRestorer {
    /// The bytes of the wallpaper store before activation.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// Base64 in the session file.
        public let storeData: Data

        public init(storeData: Data) {
            self.storeData = storeData
        }
    }

    /// The displays changed by apply and the fingerprint of the store the agent persisted.
    public struct AppliedState: Codable, Equatable, Sendable {
        public let displays: [DisplayIdentifier]
        public let fingerprint: WallpaperStoreFingerprint

        public init(displays: [DisplayIdentifier], fingerprint: WallpaperStoreFingerprint) {
            self.displays = displays
            self.fingerprint = fingerprint
        }
    }

    static let restartWallpaperAgent = ProcessCommand(
        executableURL: URL(filePath: "/usr/bin/killall"),
        arguments: ["WallpaperAgent"],
        timeout: .seconds(10),
    )

    private static let signalledExitCode: Int32 = 0
    // Same reading of man killall as DesktopIconsAction (ADR-035): exit 1 means no process was found or none was
    // signalled. The store is written either way and the agent reads it at its next launch. Not observed.
    private static let notSignalledExitCode: Int32 = 1

    private let fileStore: any FileStore
    private let processRunner: any ProcessRunner
    private let storeInspector: any WallpaperStoreInspector
    private let storeURL: URL

    public var identifier: ActionIdentifier {
        .wallpaper
    }

    /// Creates the restorer over its ports and the store location.
    public init(
        fileStore: any FileStore,
        processRunner: any ProcessRunner,
        storeInspector: any WallpaperStoreInspector,
        storeURL: URL,
    ) {
        self.fileStore = fileStore
        self.processRunner = processRunner
        self.storeInspector = storeInspector
        self.storeURL = storeURL
    }

    /// Writes the captured store bytes back and restarts the wallpaper agent, unless the store already holds exactly
    /// those bytes (nothing to do) or its fingerprint no longer equals the applied one (the user changed the
    /// wallpaper; skipped). `applied: nil` skips the fingerprint check and restores unconditionally.
    ///
    /// - Throws: ``WallpaperActionError/storeUnavailable``, ``WallpaperStoreError`` (no guess when the current store
    ///   cannot be inspected), errors of ``FileStore``, ``ProcessError``, or
    ///   ``WallpaperActionError/wallpaperAgentRestartFailed(exitCode:)``.
    public func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome {
        guard let current = try await fileStore.read(storeURL) else {
            throw WallpaperActionError.storeUnavailable
        }
        guard current != snapshot.storeData else {
            return .restored
        }
        if let applied, try storeInspector.fingerprint(of: current) != applied.fingerprint {
            return .skippedBecauseChangedByUser
        }
        try await fileStore.write(snapshot.storeData, to: storeURL)
        let result = try await processRunner.run(Self.restartWallpaperAgent)
        guard result.exitCode == Self.signalledExitCode || result.exitCode == Self.notSignalledExitCode else {
            throw WallpaperActionError.wallpaperAgentRestartFailed(exitCode: result.exitCode)
        }
        return .restored
    }
}
