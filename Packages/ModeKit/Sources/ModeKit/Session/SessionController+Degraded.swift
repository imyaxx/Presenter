import Foundation

extension SessionController {
    /// Reloads `session.json` and restores what it holds, with the same rules as recovery. A file that was unreadable
    /// may have become readable; a file that is gone ends in idle with ``RecoveryOutcome/nothingToRecover``.
    ///
    /// Performed only from ``SessionState/degraded(_:)``, and not while another retry or discard runs; otherwise
    /// ignored.
    public func retryRestore() async -> TriggerResult<RecoveryOutcome> {
        guard case .degraded = state, !isResolvingDegradedState else {
            return ignore(.retryRestore)
        }
        isResolvingDegradedState = true
        defer { isResolvingDegradedState = false }
        return .performed(await restoreFromSessionFile())
    }

    /// Removes an unreadable `session.json` and returns to idle. This is the user's explicit decision that the
    /// unreadable data is abandoned; changes it may describe are not reverted.
    ///
    /// Performed only from ``DegradedReason/unreadableSessionFile(_:)``, and not while a retry runs; otherwise ignored.
    /// - Throws: ``SessionError/sessionStoreFailed(_:)`` when the file cannot be removed; the state stays degraded.
    public func discardUnreadableSession() async throws(SessionError) -> TriggerResult<Void> {
        guard case .degraded(.unreadableSessionFile) = state, !isResolvingDegradedState else {
            return ignore(.discardUnreadableSession)
        }
        isResolvingDegradedState = true
        defer { isResolvingDegradedState = false }
        do {
            try await sessionStore.clearSession()
        } catch {
            let storeError = StoreError(sessionStoreError: error)
            logger.log(.sessionFileFailed(sessionID: nil, .remove, storeError))
            throw .sessionStoreFailed(storeError)
        }
        transition(to: .idle)
        return .performed(())
    }
}
