import Foundation

extension SessionController {
    /// Restores a session left behind by a crash or reboot, from `session.json` and the restorers alone (never the
    /// profile). Runs once; later calls return ``RecoveryOutcome/alreadyAttempted``. Must finish before any activation.
    ///
    /// A corrupted or newer `session.json` is left untouched and the state becomes degraded
    /// (``RecoveryOutcome/blocked(_:)``). Restore failures keep their records and degrade. No timer starts afterwards.
    public func recoverIfNeeded() async -> RecoveryOutcome {
        guard recoveryProgress == .notStarted else {
            return .alreadyAttempted
        }
        recoveryProgress = .running
        cancelAutoExitTimer()
        logger.log(.recoveryStarted)
        let outcome = await restoreFromSessionFile()
        recoveryProgress = .finished
        logger.log(.recoveryFinished(outcome))
        return outcome
    }

    func restoreFromSessionFile() async -> RecoveryOutcome {
        let record: SessionRecord?
        do {
            record = try await sessionStore.loadSession()
        } catch {
            let storeError = StoreError(sessionStoreError: error)
            transition(to: .degraded(.unreadableSessionFile(storeError)))
            return .blocked(storeError)
        }
        guard let record else {
            transition(to: .idle)
            return .nothingToRecover
        }
        let session = ActiveSession(record)
        transition(to: .restoring(sessionID: session.sessionID, profileName: session.profileName))
        let entries = record.actions.map { action in
            RestorePass.Entry(record: action, restorer: makeRestorer(for: action.identifier))
        }
        let result = await RestorePass(logger: logger).run(entries, sessionID: session.sessionID)
        // After a complete restore, a failure to remove session.json is logged by `settle` and harmless: the next
        // activation overwrites the file and a later recovery restores conditionally.
        _ = await settle(result, session: session)
        return result.failedRecords.isEmpty ? .restored(result.report) : .partiallyRestored(result.report)
    }

    private func makeRestorer(for identifier: ActionIdentifier) -> Result<AnyActionRestorer, any Error> {
        Result { AnyActionRestorer(try actionFactory.makeRestorer(for: identifier)) }
    }
}
