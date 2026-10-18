import Foundation

/// Restores records in reverse order. One failing action never stops the others.
struct RestorePass {
    /// A record and the restorer for it, or the error that prevented building one.
    struct Entry {
        let record: ActionRecord
        let restorer: Swift.Result<AnyActionRestorer, any Error>
    }

    struct Result {
        let report: RestoreReport
        /// The records whose restore failed, in their original (apply) order, to keep in `session.json`.
        let failedRecords: [ActionRecord]
    }

    let logger: any SessionLogger

    func run(_ entries: [Entry], sessionID: UUID) async -> Result {
        var restored: [ActionIdentifier] = []
        var skipped: [ActionIdentifier] = []
        var failures: [ActionFailure] = []
        var failedRecords: [ActionRecord] = []
        for entry in entries.reversed() {
            let identifier = entry.record.identifier
            do {
                switch try await entry.restorer.get().restore(entry.record) {
                case .restored:
                    restored.append(identifier)
                    logger.log(.actionRestored(sessionID: sessionID, identifier))
                case .skippedBecauseChangedByUser:
                    skipped.append(identifier)
                    logger.log(.actionSkippedBecauseChangedByUser(sessionID: sessionID, identifier))
                }
            } catch {
                let failure = ActionFailure(identifier: identifier, error: error)
                failures.append(failure)
                failedRecords.insert(entry.record, at: 0)
                logger.log(.actionFailed(sessionID: sessionID, identifier, phase: .restore, reason: failure.reason))
            }
        }
        let report = RestoreReport(restored: restored, skippedBecauseChangedByUser: skipped, failed: failures)
        return Result(report: report, failedRecords: failedRecords)
    }
}
