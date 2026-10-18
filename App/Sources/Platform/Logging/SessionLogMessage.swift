import Foundation
import ModeKit

/// The log line for one ``SessionEvent``: a level, a public text and an optional private detail (ADR-040).
///
/// The public text holds only states, action identifiers, phases and session IDs. `reason` strings and store errors,
/// which may contain paths, and profile names go to the private detail only. A pure function, so the text is tested
/// without reading the unified log.
struct SessionLogMessage: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case info, error
    }

    let level: Level
    let publicText: String
    let privateDetail: String?

    init(level: Level, publicText: String, privateDetail: String? = nil) {
        self.level = level
        self.publicText = publicText
        self.privateDetail = privateDetail
    }

    init(_ event: SessionEvent) {
        switch event {
        case .stateChanged(let previous, let current, let sessionID):
            self.init(
                level: .info,
                publicText: "state \(Self.name(of: previous)) -> \(Self.name(of: current))\(Self.suffix(sessionID))",
            )
        case .triggerIgnored(let trigger, let state):
            self.init(level: .info, publicText: "trigger \(trigger) ignored in state \(Self.name(of: state))")
        case .actionCaptured(let sessionID, let action):
            self.init(level: .info, publicText: "action \(action.rawValue) captured\(Self.suffix(sessionID))")
        case .actionApplied(let sessionID, let action):
            self.init(level: .info, publicText: "action \(action.rawValue) applied\(Self.suffix(sessionID))")
        case .actionRestored(let sessionID, let action):
            self.init(level: .info, publicText: "action \(action.rawValue) restored\(Self.suffix(sessionID))")
        case .actionSkippedBecauseChangedByUser(let sessionID, let action):
            self.init(
                level: .info,
                publicText: "action \(action.rawValue) skipped, changed by the user\(Self.suffix(sessionID))",
            )
        case .actionFailed(let sessionID, let action, let phase, let reason):
            self.init(
                level: .error,
                publicText: "action \(action.rawValue) failed in \(phase)\(Self.suffix(sessionID))",
                privateDetail: reason,
            )
        case .recoveryStarted:
            self.init(level: .info, publicText: "recovery started")
        case .recoveryFinished(let outcome):
            self = Self.recoveryMessage(outcome)
        case .sessionFileFailed(let sessionID, let operation, let error):
            self.init(
                level: .error,
                publicText: "session file \(operation) failed\(Self.suffix(sessionID))",
                privateDetail: String(describing: error),
            )
        }
    }

    private static func recoveryMessage(_ outcome: RecoveryOutcome) -> SessionLogMessage {
        switch outcome {
        case .nothingToRecover:
            SessionLogMessage(level: .info, publicText: "recovery finished, nothing to recover")
        case .restored(let report):
            SessionLogMessage(level: .info, publicText: "recovery finished, \(summary(of: report))")
        case .partiallyRestored(let report):
            SessionLogMessage(
                level: .error,
                publicText: "recovery finished partially, \(summary(of: report))",
                privateDetail: report.failed.map { "\($0.identifier.rawValue): \($0.reason)" }.joined(separator: "; "),
            )
        case .blocked(let error):
            SessionLogMessage(
                level: .error,
                publicText: "recovery blocked by the session file",
                privateDetail: String(describing: error),
            )
        case .alreadyAttempted:
            SessionLogMessage(level: .info, publicText: "recovery already attempted")
        }
    }

    private static func summary(of report: RestoreReport) -> String {
        let restored = report.restored.map(\.rawValue).joined(separator: ",")
        let skipped = report.skippedBecauseChangedByUser.map(\.rawValue).joined(separator: ",")
        let failed = report.failed.map(\.identifier.rawValue).joined(separator: ",")
        return "restored [\(restored)] skipped [\(skipped)] failed [\(failed)]"
    }

    /// The state's case name only: no profile name, no failure reason.
    private static func name(of state: SessionState) -> String {
        switch state {
        case .idle: "idle"
        case .applying: "applying"
        case .active: "active"
        case .restoring: "restoring"
        case .rollingBack: "rollingBack"
        case .degraded(.restoreFailed): "degraded(restoreFailed)"
        case .degraded(.unreadableSessionFile): "degraded(unreadableSessionFile)"
        }
    }

    private static func suffix(_ sessionID: UUID?) -> String {
        sessionID.map { " session=\($0.uuidString)" } ?? ""
    }
}
