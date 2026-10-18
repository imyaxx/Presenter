import Foundation

/// Applies actions in profile order and persists each record with its applied state right after the apply.
struct ApplyPass {
    enum Result {
        case applied([ActionRecord])
        /// `rollbackRecords` are the applied records plus the failing action's record, in apply order. The failing
        /// record has nil `appliedData` when the apply threw, or its in-memory applied state when only persisting
        /// it failed.
        case failed(ActionFailure, rollbackRecords: [ActionRecord])
    }

    let sessionStore: SessionStore
    let logger: any SessionLogger

    func run(
        _ actions: [AnyModeAction],
        records capturedRecords: [ActionRecord],
        session: ActiveSession,
    ) async -> Result {
        var records = capturedRecords
        for (index, action) in actions.enumerated() {
            let appliedData: Data
            do {
                appliedData = try await action.apply()
            } catch {
                let failure = ActionFailure(identifier: action.identifier, error: error)
                logger.log(
                    .actionFailed(
                        sessionID: session.sessionID, action.identifier, phase: .apply, reason: failure.reason, )
                )
                return .failed(failure, rollbackRecords: Array(records[...index]))
            }
            let snapshotData = records[index].snapshotData
            records[index] = ActionRecord(
                identifier: action.identifier, snapshotData: snapshotData, appliedData: appliedData, )
            logger.log(.actionApplied(sessionID: session.sessionID, action.identifier))
            do {
                try await sessionStore.saveSession(session.record(with: records))
            } catch {
                let storeError = StoreError(sessionStoreError: error)
                logger.log(.sessionFileFailed(sessionID: session.sessionID, .write, storeError))
                let failure = ActionFailure(identifier: action.identifier, error: storeError)
                return .failed(failure, rollbackRecords: Array(records[...index]))
            }
        }
        return .applied(records)
    }
}
