import ModeKit

/// A dismissible message under the state line. Mapped from action identifiers, phases and error cases only, never from
/// a failure's `reason` text (ADR-043).
enum MenuBarNotice: Equatable, Sendable {
    /// How far a failed activation got.
    enum ActivationOutcome: Equatable, Sendable {
        /// Reading the current state failed; nothing was changed.
        case nothingChanged
        /// Applying failed; every applied change was undone.
        case undone
        /// Applying failed and some changes could not be undone; Retry restore is offered.
        case partlyUndone
    }

    case activationFailed(ActionIdentifier, ActivationOutcome)
    case invalidProfile
    case notReady
    case sessionFileNotSaved
    case sessionFileNotRemoved
    /// Actions left as the user changed them during the session.
    case keptUserChanges([ActionIdentifier])
    case recoveredAfterInterruption(kept: [ActionIdentifier])
    case profilesFolderUnavailable
    case discardFailed

    /// The notice for a failed activation.
    static func activationFailure(_ error: SessionError) -> MenuBarNotice {
        switch error {
        case .captureFailed(let failure):
            .activationFailed(failure.identifier, .nothingChanged)
        case .applyFailed(let failure, let rollback):
            .activationFailed(failure.identifier, rollback.failed.isEmpty ? .undone : .partlyUndone)
        case .invalidProfile:
            .invalidProfile
        case .recoveryNotRun:
            .notReady
        case .sessionStoreFailed:
            .sessionFileNotSaved
        }
    }

    /// The notice after a finished restore: the actions the user changed meanwhile, if any.
    static func afterRestore(_ report: RestoreReport) -> MenuBarNotice? {
        report.skippedBecauseChangedByUser.isEmpty ? nil : .keptUserChanges(report.skippedBecauseChangedByUser)
    }

    /// The notice after launch recovery: only when an interrupted session was restored.
    static func afterRecovery(_ outcome: RecoveryOutcome) -> MenuBarNotice? {
        guard case .restored(let report) = outcome else {
            return nil
        }
        return .recoveredAfterInterruption(kept: report.skippedBecauseChangedByUser)
    }

    /// A failed Dock action usually means the Automation permission for System Events is missing (ADR-025).
    var mentionsAutomationPermission: Bool {
        if case .activationFailed(.dock, _) = self { true } else { false }
    }
}
