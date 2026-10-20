import ModeKit

/// What the popover and the icon show for the session, derived from `SessionState` (ADR-043).
enum MenuBarPresentation: Equatable, Sendable {
    /// The app could not build its session graph; it never activates anything.
    case unavailable
    /// Launch recovery has not finished; no trigger is offered.
    case recoveringAtLaunch
    case idle
    case applying(profileName: String)
    case active(ActiveSession)
    case restoring(profileName: String)
    case rollingBack(profileName: String)
    /// Some actions could not be restored; their records stay in `session.json`.
    case restoreFailed(profileName: String, actions: [ActionIdentifier])
    /// `session.json` is corrupted or newer; it is left untouched.
    case unreadableSessionFile

    init(_ state: SessionState) {
        switch state {
        case .idle: self = .idle
        case .applying(_, let name): self = .applying(profileName: name)
        case .active(let session): self = .active(session)
        case .restoring(_, let name): self = .restoring(profileName: name)
        case .rollingBack(_, let name): self = .rollingBack(profileName: name)
        case .degraded(.restoreFailed(_, let name, let failures)):
            self = .restoreFailed(profileName: name, actions: failures.map(\.identifier))
        case .degraded(.unreadableSessionFile): self = .unreadableSessionFile
        }
    }

    var acceptsActivation: Bool {
        self == .idle
    }

    var acceptsStop: Bool {
        if case .active = self { true } else { false }
    }

    var acceptsRetry: Bool {
        switch self {
        case .restoreFailed, .unreadableSessionFile: true
        case .unavailable, .recoveringAtLaunch, .idle, .applying, .active, .restoring, .rollingBack: false
        }
    }

    var acceptsDiscard: Bool {
        self == .unreadableSessionFile
    }

    /// The icon shape this presentation shows, or nil to keep the previous one (applying, restoring, rolling back).
    var iconShape: MenuBarIconShape? {
        switch self {
        case .recoveringAtLaunch, .idle: .idle
        case .active: .active
        case .unavailable, .restoreFailed, .unreadableSessionFile: .needsAttention
        case .applying, .restoring, .rollingBack: nil
        }
    }
}
