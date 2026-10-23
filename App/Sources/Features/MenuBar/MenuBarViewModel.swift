import ModeKit
import Observation

/// State and intents of the menu-bar popover and icon (ADR-043). No system calls, no UI text: views map the values
/// through `L10n`.
///
/// Triggers the presentation does not accept are ignored here as well as disabled in the view, and one trigger runs
/// at a time, so a double click cannot start two activations. A `TriggerResult.ignored` is never shown as an error.
@MainActor
@Observable
final class MenuBarViewModel {
    private(set) var presentation: MenuBarPresentation
    private(set) var iconShape: MenuBarIconShape
    private(set) var profiles: [Profile] = []
    private(set) var profilesProblem: ProfilesProblem?
    private(set) var notice: MenuBarNotice?
    private(set) var isConfirmingDiscard = false
    private(set) var isTriggerRunning = false

    private let services: MenuBarServices?
    private var hasRecovered = false
    private var latestState = SessionState.idle

    /// A view model over working services; it shows "Restoring" until ``recoverAtLaunch()`` has finished.
    convenience init(services: MenuBarServices) {
        self.init(services: services, presentation: .recoveringAtLaunch)
    }

    /// A view model for an app that could not build its session graph: it offers nothing but Quit.
    static func unavailable() -> MenuBarViewModel {
        MenuBarViewModel(services: nil, presentation: .unavailable)
    }

    private init(services: MenuBarServices?, presentation: MenuBarPresentation) {
        self.services = services
        self.presentation = presentation
        iconShape = presentation.iconShape ?? .idle
    }

    var canActivate: Bool {
        presentation.acceptsActivation && !isTriggerRunning
    }

    var canStop: Bool {
        presentation.acceptsStop && !isTriggerRunning
    }

    var canRetryRestore: Bool {
        presentation.acceptsRetry && !isTriggerRunning
    }

    var canDiscardSessionFile: Bool {
        presentation.acceptsDiscard && !isTriggerRunning
    }

    /// Follows the controller's states until the stream ends or the calling task is cancelled.
    func follow(_ updates: AsyncStream<SessionState>) async {
        for await state in updates {
            latestState = state
            refreshPresentation()
        }
    }

    /// Runs launch recovery once, then shows the real state and loads the profiles.
    func recoverAtLaunch() async {
        guard let services, !hasRecovered else {
            return
        }
        let outcome = await services.session.recoverIfNeeded()
        hasRecovered = true
        if let recoveryNotice = MenuBarNotice.afterRecovery(outcome) {
            notice = recoveryNotice
        }
        refreshPresentation()
        await reloadProfiles()
    }

    /// Reloads the profiles each time the popover opens, so a hand-edited `profiles.json` shows without a relaunch.
    func popoverDidOpen() async {
        await reloadProfiles()
    }

    func activate(_ profile: Profile) async {
        guard let services, canActivate else {
            return
        }
        isTriggerRunning = true
        defer { isTriggerRunning = false }
        do {
            if case .performed = try await services.session.activate(profile) {
                notice = nil
            }
        } catch {
            notice = .activationFailure(error)
        }
    }

    func deactivate() async {
        guard let services, canStop else {
            return
        }
        isTriggerRunning = true
        defer { isTriggerRunning = false }
        do {
            if case .performed(let report) = try await services.session.deactivate() {
                notice = .afterRestore(report)
            }
        } catch {
            notice = .sessionFileNotRemoved
        }
    }

    func retryRestore() async {
        guard let services, canRetryRestore else {
            return
        }
        isTriggerRunning = true
        defer { isTriggerRunning = false }
        if case .performed(.restored(let report)) = await services.session.retryRestore() {
            notice = .afterRestore(report)
        }
    }

    /// First step of discarding an unreadable `session.json`: asks for an inline confirmation.
    func requestDiscardUnreadableSession() {
        guard canDiscardSessionFile else {
            return
        }
        isConfirmingDiscard = true
    }

    func cancelDiscard() {
        isConfirmingDiscard = false
    }

    func confirmDiscard() async {
        guard let services, isConfirmingDiscard, canDiscardSessionFile else {
            return
        }
        isConfirmingDiscard = false
        isTriggerRunning = true
        defer { isTriggerRunning = false }
        do {
            _ = try await services.session.discardUnreadableSession()
        } catch {
            notice = .discardFailed
        }
    }

    func revealProfilesFolder() async {
        guard let services else {
            return
        }
        do {
            try await services.folderRevealer.revealProfilesFolder()
        } catch {
            notice = .profilesFolderUnavailable
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func reloadProfiles() async {
        guard let services else {
            return
        }
        do {
            profiles = try await services.profiles.loadProfiles()
            profilesProblem = nil
        } catch {
            profiles = []
            profilesProblem = ProfilesProblem(error)
        }
    }

    private func refreshPresentation() {
        guard presentation != .unavailable else {
            return
        }
        presentation = hasRecovered ? MenuBarPresentation(latestState) : .recoveringAtLaunch
        if let shape = presentation.iconShape {
            iconShape = shape
        }
        if !presentation.acceptsDiscard {
            isConfirmingDiscard = false
        }
    }
}
