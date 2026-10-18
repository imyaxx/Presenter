/// Unhides the applications a ``HideAppsAction`` hid (ADR-009, ADR-036). Needs no profile, so crash recovery builds
/// it from the action identifier alone.
///
/// An application that is no longer running is never relaunched. One that is running and visible again was unhidden
/// by the user (or by the system when the user switched to it) and is left alone.
///
/// Threading: a value type holding its port; safe to use from any context.
public struct HideAppsRestorer: ActionRestorer {
    /// The applications that could be hidden at capture: visible, not this application, not frontmost, not excluded.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// Sorted by raw value, without duplicates.
        public let candidates: [BundleIdentifier]

        public init(candidates: [BundleIdentifier]) {
            self.candidates = candidates
        }
    }

    /// The applications that accepted the hide request, in snapshot order.
    public struct AppliedState: Codable, Equatable, Sendable {
        public let hidden: [BundleIdentifier]

        public init(hidden: [BundleIdentifier]) {
            self.hidden = hidden
        }
    }

    private let workspace: any WorkspaceAdapter

    public var identifier: ActionIdentifier {
        .hideApps
    }

    /// Creates the restorer over its port.
    public init(workspace: any WorkspaceAdapter) {
        self.workspace = workspace
    }

    /// Unhides each application of `applied.hidden` (or of `snapshot.candidates` when `applied` is nil, after an
    /// interrupted apply) that is still running and hidden.
    ///
    /// Returns ``RestoreOutcome/skippedBecauseChangedByUser`` when none was unhidden by this call and at least one was
    /// found running and visible; otherwise ``RestoreOutcome/restored``.
    ///
    /// - Throws: ``HideAppsActionError/couldNotUnhide(_:)`` after attempting all, when any application refused.
    public func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome {
        let toUnhide = applied?.hidden ?? snapshot.candidates
        guard !toUnhide.isEmpty else {
            return .restored
        }
        let running = await workspace.runningApplications()
        let runningIdentifiers = Set(running.map(\.bundleIdentifier))
        let hiddenIdentifiers = Set(running.filter(\.isHidden).map(\.bundleIdentifier))
        var unhiddenCount = 0
        var visibleCount = 0
        var refused: [BundleIdentifier] = []
        for application in toUnhide where runningIdentifiers.contains(application) {
            guard hiddenIdentifiers.contains(application) else {
                visibleCount += 1
                continue
            }
            switch await workspace.unhide(application) {
            case .changed: unhiddenCount += 1
            case .notRunning: continue
            case .refused: refused.append(application)
            }
        }
        guard refused.isEmpty else {
            throw HideAppsActionError.couldNotUnhide(refused)
        }
        return unhiddenCount == 0 && visibleCount > 0 ? .skippedBecauseChangedByUser : .restored
    }
}
