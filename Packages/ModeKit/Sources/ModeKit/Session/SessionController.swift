import Foundation

/// Owns the session state machine: activate a profile, deactivate it, roll back a failed activation, recover after
/// a crash, and auto-exit. See docs/01-architecture.md.
///
/// Threading and reentrancy: an actor. Every trigger reads the state and, when it accepts the trigger, sets the next
/// state before its first suspension. A trigger the current state does not accept returns
/// ``TriggerResult/ignored(currentState:)``, is logged, and is never queued.
public actor SessionController {
    enum RecoveryProgress {
        case notStarted, running, finished
    }

    /// An applied session: its identity, its records with applied state, and the restorers built at activation.
    struct AppliedSession {
        let session: ActiveSession
        let records: [ActionRecord]
        let restorers: [ActionIdentifier: AnyActionRestorer]
    }

    let actionFactory: any ActionFactory
    let sessionStore: SessionStore
    let clock: any SessionClock
    let logger: any SessionLogger
    /// The current state. Every change is also delivered by ``stateUpdates()``.
    public private(set) var state = SessionState.idle
    var recoveryProgress = RecoveryProgress.notStarted
    var appliedSession: AppliedSession?
    var autoExitTask: Task<Void, Never>?
    private let statePublisher = StatePublisher()

    /// Creates an idle controller. Call ``recoverIfNeeded()`` once at launch before any activation.
    public init(
        actionFactory: any ActionFactory,
        sessionStore: SessionStore,
        clock: any SessionClock,
        logger: any SessionLogger,
    ) {
        self.actionFactory = actionFactory
        self.sessionStore = sessionStore
        self.clock = clock
        self.logger = logger
    }

    /// A stream that yields the current state first, then every change, until the subscriber stops iterating.
    public func stateUpdates() -> AsyncStream<SessionState> {
        statePublisher.subscribe(startingWith: state)
    }

    /// Activates `profile`: captures every action in step order, writes `session.json` before the first apply,
    /// applies in step order persisting each applied record, and starts the auto-exit timer when the profile has one.
    ///
    /// Performed only from ``SessionState/idle``; otherwise ignored.
    /// - Throws: ``SessionError/recoveryNotRun``, ``SessionError/invalidProfile(_:)`` (nothing touched),
    ///   ``SessionError/captureFailed(_:)`` or ``SessionError/sessionStoreFailed(_:)`` (nothing applied, back to
    ///   idle), ``SessionError/applyFailed(_:rollback:)`` (rolled back; idle, or degraded if a rollback restore
    ///   failed).
    public func activate(_ profile: Profile) async throws(SessionError) -> TriggerResult<ActiveSession> {
        guard recoveryProgress == .finished else {
            throw .recoveryNotRun
        }
        guard case .idle = state else {
            return ignore(.activate)
        }
        let validated: Profile
        do {
            validated = try ProfileValidation.validate(profile)
        } catch {
            throw .invalidProfile(error)
        }
        let actions = try makeActions(for: validated.steps)
        let session = ActiveSession(
            sessionID: UUID(),
            profileID: validated.id,
            profileName: validated.name,
            startedAt: clock.now(),
        )
        transition(to: .applying(sessionID: session.sessionID, profileName: session.profileName))
        let records = try await captureAndPersist(actions, session: session)
        // Unique keys: validation rejected duplicate step kinds, and each kind has exactly one action identifier.
        let restorers = Dictionary(uniqueKeysWithValues: actions.map { ($0.identifier, $0.restorer) })
        let applyPass = ApplyPass(sessionStore: sessionStore, logger: logger)
        switch await applyPass.run(actions, records: records, session: session) {
        case .applied(let appliedRecords):
            appliedSession = AppliedSession(session: session, records: appliedRecords, restorers: restorers)
            transition(to: .active(session))
            if let autoExit = validated.autoExit {
                startAutoExitTimer(after: autoExit, sessionID: session.sessionID)
            }
            return .performed(session)
        case .failed(let failure, let rollbackRecords):
            throw await rollBack(after: failure, records: rollbackRecords, restorers: restorers, session: session)
        }
    }

    func transition(to newState: SessionState) {
        guard newState != state else {
            return
        }
        let previous = state
        state = newState
        logger.log(
            .stateChanged(previous: previous, current: newState, sessionID: newState.sessionID ?? previous.sessionID))
        statePublisher.publish(newState)
    }

    func ignore<Value: Sendable>(_ trigger: SessionEvent.Trigger) -> TriggerResult<Value> {
        logger.log(.triggerIgnored(trigger, state: state))
        return .ignored(currentState: state)
    }

    private func makeActions(for steps: [ProfileStep]) throws(SessionError) -> [AnyModeAction] {
        var actions: [AnyModeAction] = []
        for step in steps {
            do {
                actions.append(AnyModeAction(try actionFactory.makeAction(for: step)))
            } catch {
                throw .captureFailed(ActionFailure(identifier: step.actionIdentifier, error: error))
            }
        }
        return actions
    }

    /// Captures every action and writes `session.json` with no applied state, before anything is applied.
    private func captureAndPersist(
        _ actions: [AnyModeAction],
        session: ActiveSession,
    ) async throws(SessionError) -> [ActionRecord] {
        switch await CapturePass(logger: logger).run(actions, sessionID: session.sessionID) {
        case .failed(let failure):
            transition(to: .idle)
            throw .captureFailed(failure)
        case .captured(let records):
            do {
                try await sessionStore.saveSession(session.record(with: records))
            } catch {
                let storeError = StoreError(sessionStoreError: error)
                logger.log(.sessionFileFailed(sessionID: session.sessionID, .write, storeError))
                transition(to: .idle)
                throw .sessionStoreFailed(storeError)
            }
            return records
        }
    }

    /// Restores what a failed activation applied, in reverse, and returns the error to throw.
    private func rollBack(
        after failure: ActionFailure,
        records: [ActionRecord],
        restorers: [ActionIdentifier: AnyActionRestorer],
        session: ActiveSession,
    ) async -> SessionError {
        cancelAutoExitTimer()
        transition(to: .rollingBack(sessionID: session.sessionID, profileName: session.profileName))
        let entries = records.map { record in
            RestorePass.Entry(record: record, restorer: Self.restorer(for: record.identifier, in: restorers))
        }
        let result = await RestorePass(logger: logger).run(entries, sessionID: session.sessionID)
        // A failure to remove or rewrite session.json is logged by `settle`; the apply failure is what the caller
        // needs.
        _ = await settle(result, session: session)
        return .applyFailed(failure, rollback: result.report)
    }

    static func restorer(
        for identifier: ActionIdentifier,
        in restorers: [ActionIdentifier: AnyActionRestorer],
    ) -> Result<AnyActionRestorer, any Error> {
        guard let restorer = restorers[identifier] else {
            return .failure(ActionError.unsupported(identifier))
        }
        return .success(restorer)
    }
}
