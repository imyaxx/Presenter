import Foundation

/// Captures every action in profile order and stops at the first failure. Changes nothing.
struct CapturePass {
    enum Result {
        case captured([ActionRecord])
        case failed(ActionFailure)
    }

    let logger: any SessionLogger

    func run(_ actions: [AnyModeAction], sessionID: UUID) async -> Result {
        var records: [ActionRecord] = []
        for action in actions {
            do {
                let snapshotData = try await action.capture()
                records.append(
                    ActionRecord(identifier: action.identifier, snapshotData: snapshotData, appliedData: nil))
                logger.log(.actionCaptured(sessionID: sessionID, action.identifier))
            } catch {
                let failure = ActionFailure(identifier: action.identifier, error: error)
                logger.log(
                    .actionFailed(sessionID: sessionID, action.identifier, phase: .capture, reason: failure.reason))
                return .failed(failure)
            }
        }
        return .captured(records)
    }
}
