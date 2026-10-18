import Foundation

/// Sets the desktop image of the current Space of each selected display (ADR-027, ADR-038, spike S2). Capture and
/// restore use the bytes of the wallpaper store; restore is done by ``WallpaperRestorer``.
///
/// Apply fails closed: the store is read and fingerprinted (``WallpaperStoreInspector``, ADR-039) before anything
/// changes, so an unknown store format stops the apply. After setting the image it polls the store until the wallpaper
/// agent has persisted a change; the fingerprint at that moment is the applied state. If the target wallpaper already
/// is the current one the store does not change and the apply fails with
/// ``WallpaperActionError/storeDidNotChange``, deliberately: a silent no-op could leave the wallpaper unhidden during a
/// screen share. Displays that are not connected are skipped. The `NSWorkspace` getters are never used.
///
/// Threading: a value type holding its ports; safe to use from any context.
public struct WallpaperAction: ModeAction {
    public typealias Snapshot = WallpaperRestorer.Snapshot
    public typealias AppliedState = WallpaperRestorer.AppliedState

    /// Polling cadence for the store after setting the image. Engineering guesses, not measurements (docs/07); the M2
    /// adapter branch measures the real latency and recalibrates.
    static let pollInterval = Duration.milliseconds(100)
    static let maximumPolls = 50

    private let choice: WallpaperChoice
    private let displays: DisplaySelection
    private let ports: ActionPorts
    private let locations: WallpaperLocations

    public var identifier: ActionIdentifier {
        .wallpaper
    }

    /// Creates the action for a profile's `wallpaper` step.
    public init(
        choice: WallpaperChoice,
        displays: DisplaySelection,
        ports: ActionPorts,
        locations: WallpaperLocations,
    ) {
        self.choice = choice
        self.displays = displays
        self.ports = ports
        self.locations = locations
    }

    /// Reads the wallpaper store bytes. Changes nothing.
    ///
    /// - Throws: ``WallpaperActionError/storeUnavailable`` or an error of ``FileStore``.
    public func capture() async throws -> Snapshot {
        Snapshot(storeData: try await readStore())
    }

    /// Fingerprints the store, sets the image on the connected selected displays in order, then waits for the agent to
    /// persist the change. With no selected display connected it changes nothing and returns no displays.
    ///
    /// - Throws: ``WallpaperStoreError`` or ``WallpaperActionError/storeUnavailable`` before any change; errors of
    ///   ``SolidColorImageRenderer``, ``FileStore`` or ``WorkspaceAdapter/setDesktopImage(_:on:)``;
    ///   ``WallpaperActionError/storeDidNotChange``; `CancellationError` while polling.
    public func apply() async throws -> AppliedState {
        let initial = try ports.storeInspector.fingerprint(of: try await readStore())
        let targets = await selectedDisplays()
        guard !targets.isEmpty else {
            return AppliedState(displays: [], fingerprint: initial)
        }
        let image = try await imageURL()
        for display in targets {
            try await ports.workspace.setDesktopImage(image, on: display)
        }
        return AppliedState(displays: targets, fingerprint: try await waitForStoreChange(from: initial))
    }

    /// Delegates to ``WallpaperRestorer/restore(_:expecting:)``.
    public func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome {
        let restorer = WallpaperRestorer(
            fileStore: ports.fileStore,
            processRunner: ports.processRunner,
            storeInspector: ports.storeInspector,
            storeURL: locations.storeURL,
        )
        return try await restorer.restore(snapshot, expecting: applied)
    }

    /// The generated PNG file for `color`: `solid-rrggbb.png`, lowercase hex.
    static func generatedImageName(for color: SolidColor) -> String {
        "solid-" + [color.red, color.green, color.blue].map { String(format: "%02x", $0) }.joined() + ".png"
    }

    private func readStore() async throws -> Data {
        guard let data = try await ports.fileStore.read(locations.storeURL) else {
            throw WallpaperActionError.storeUnavailable
        }
        return data
    }

    private func selectedDisplays() async -> [DisplayIdentifier] {
        let connected = Set(await ports.workspace.connectedDisplays())
        switch displays {
        case .allDisplays:
            return connected.sorted()
        case .specific(let selected):
            return connected.intersection(selected).sorted()
        }
    }

    private func imageURL() async throws -> URL {
        switch choice {
        case .image(let url):
            return url
        case .solidColor(let color):
            let data = try await ports.imageRenderer.pngData(for: color)
            let url = locations.generatedImagesDirectory.appending(path: Self.generatedImageName(for: color))
            try await ports.fileStore.write(data, to: url)
            return url
        }
    }

    private func waitForStoreChange(from initial: WallpaperStoreFingerprint) async throws -> WallpaperStoreFingerprint {
        for _ in 0..<Self.maximumPolls {
            try await ports.clock.sleep(for: Self.pollInterval)
            let current = try ports.storeInspector.fingerprint(of: try await readStore())
            if current != initial {
                return current
            }
        }
        throw WallpaperActionError.storeDidNotChange
    }
}
