/// Hides the visible regular applications for the session, except this application, the frontmost one and the
/// profile's exclusions (ADR-009, ADR-036). Restore is done by ``HideAppsRestorer``.
///
/// Applications already hidden before activation are never touched and stay hidden after. An application that
/// refuses to hide or quits before it is hidden is skipped and is not an error. ``ApplicationVisibilityChange/changed``
/// means the request was accepted; the effect is not observed.
///
/// Threading: a value type holding its port; safe to use from any context.
public struct HideAppsAction: ModeAction {
    public typealias Snapshot = HideAppsRestorer.Snapshot
    public typealias AppliedState = HideAppsRestorer.AppliedState

    private let exclusions: Set<BundleIdentifier>
    private let workspace: any WorkspaceAdapter

    public var identifier: ActionIdentifier {
        .hideApps
    }

    /// Creates the action for a profile's `hideApps` step.
    public init(exclusions: Set<BundleIdentifier>, workspace: any WorkspaceAdapter) {
        self.exclusions = exclusions
        self.workspace = workspace
    }

    /// Lists the candidates. Changes nothing.
    public func capture() async throws -> Snapshot {
        Snapshot(candidates: await candidates())
    }

    /// Asks each candidate, listed again now, to hide. Never fails because of an application.
    ///
    /// - Returns: The candidates that accepted, possibly none.
    public func apply() async throws -> AppliedState {
        var hidden: [BundleIdentifier] = []
        for application in await candidates() where await workspace.hide(application) == .changed {
            hidden.append(application)
        }
        return AppliedState(hidden: hidden)
    }

    /// Delegates to ``HideAppsRestorer/restore(_:expecting:)``.
    ///
    /// - Throws: ``HideAppsActionError/couldNotUnhide(_:)``.
    public func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome {
        try await HideAppsRestorer(workspace: workspace).restore(snapshot, expecting: applied)
    }

    private func candidates() async -> [BundleIdentifier] {
        let visible = await workspace.runningApplications().filter { application in
            !application.isHidden && !application.isThisApplication && !application.isFrontmost
                && !exclusions.contains(application.bundleIdentifier)
        }
        return Set(visible.map(\.bundleIdentifier)).sorted()
    }
}
