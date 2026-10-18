import Foundation

extension SessionController {
    /// Restores every action in reverse order. One failing action never stops the others; failures are in the
    /// report, not thrown. When all actions are restored or skipped, `session.json` is removed and the state becomes
    /// idle; otherwise only the failed records stay in `session.json` and the state becomes degraded.
    ///
    /// Performed only from ``SessionState/active(_:)``; otherwise ignored. Cancels the auto-exit timer.
    /// - Throws: ``SessionError/sessionStoreFailed(_:)`` when removing `session.json` fails after a complete
    ///   restore. The state is idle then: the stale file is harmless, because the next activation overwrites it and
    ///   a recovery restores conditionally.
    public func deactivate() async throws(SessionError) -> TriggerResult<RestoreReport> {
        switch await restoreAppliedSession(trigger: .deactivate) {
        case .ignored(let currentState):
            return .ignored(currentState: currentState)
        case .performed(let restoration):
            if let removalError = restoration.removalError {
                throw .sessionStoreFailed(removalError)
            }
            return .performed(restoration.report)
        }
    }

    struct Restoration: Sendable {
        let report: RestoreReport
        let removalError: StoreError?
    }

    func restoreAppliedSession(trigger: SessionEvent.Trigger) async -> TriggerResult<Restoration> {
        guard case .active = state, let applied = appliedSession else {
            return ignore(trigger)
        }
        cancelAutoExitTimer()
        appliedSession = nil
        let session = applied.session
        transition(to: .restoring(sessionID: session.sessionID, profileName: session.profileName))
        let entries = applied.records.map { record in
            RestorePass.Entry(record: record, restorer: Self.restorer(for: record.identifier, in: applied.restorers))
        }
        let result = await RestorePass(logger: logger).run(entries, sessionID: session.sessionID)
        let removalError = await settle(result, session: session)
        return .performed(Restoration(report: result.report, removalError: removalError))
    }

    /// Ends a restore pass. Nothing failed: remove `session.json`, go idle. Something failed: keep only the failed
    /// records in `session.json` and degrade.
    ///
    /// - Returns: The error of removing `session.json` after a complete restore, already logged. A failure to
    ///   rewrite the failed records is logged and the state still degrades.
    func settle(_ result: RestorePass.Result, session: ActiveSession) async -> StoreError? {
        guard result.failedRecords.isEmpty else {
            do {
                try await sessionStore.saveSession(session.record(with: result.failedRecords))
            } catch {
                logger.log(
                    .sessionFileFailed(sessionID: session.sessionID, .write, StoreError(sessionStoreError: error)))
            }
            let reason = DegradedReason.restoreFailed(
                sessionID: session.sessionID,
                profileName: session.profileName,
                failures: result.report.failed,
            )
            transition(to: .degraded(reason))
            return nil
        }
        do {
            try await sessionStore.clearSession()
            transition(to: .idle)
            return nil
        } catch {
            let storeError = StoreError(sessionStoreError: error)
            logger.log(.sessionFileFailed(sessionID: session.sessionID, .remove, storeError))
            transition(to: .idle)
            return storeError
        }
    }

    func startAutoExitTimer(after autoExit: AutoExit, sessionID: UUID) {
        autoExitTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: autoExit.duration)
            } catch {
                // Cancelled by deactivate, rollback or recovery: a cancelled timer must not end the session.
                return
            }
            await self?.autoExitTimerFired(sessionID: sessionID)
        }
    }

    func cancelAutoExitTimer() {
        autoExitTask?.cancel()
        autoExitTask = nil
    }

    private func autoExitTimerFired(sessionID: UUID) async {
        guard case .active(let session) = state, session.sessionID == sessionID else {
            logger.log(.triggerIgnored(.autoExitTimer, state: state))
            return
        }
        // The outcome, including a failure to remove session.json, is already logged by `settle`.
        _ = await restoreAppliedSession(trigger: .autoExitTimer)
    }
}
