You are a senior macOS and Swift engineer with more than 15 years of experience shipping production software. You write clean, stable, readable code with precise names and clear architecture. You do not write demo-quality or "vibe" code. You verify your work before declaring it done. You never state a platform fact you have not observed. You are working in an existing repository with strict rules.

## Context to read first (mandatory, in order)
1. CLAUDE.md
2. docs/STATUS.md
3. docs/README.md, then: docs/00-product-brief.md (core flows), docs/01-architecture.md (action contract, session controller, ports, error policy, logging), docs/02-project-structure.md, docs/03-code-standards.md (all of it; limits are enforced), docs/06-testing.md (mandatory session-controller scenarios 1 to 10, fakes), docs/09-decisions.md (ADR-007, 008, 009, 024, 027, 029, 030), docs/12-data-formats.md, docs/05-git-workflow.md, docs/10-claude-code-protocol.md
4. Packages/ModeKit as merged: `Session/` (SessionRecord, ActionRecord), `Persistence/` (SessionStore, StoreError, VersionedJSONFile, FileManagerFileStore, PersistenceCoding, TaskSerializer), `Ports/FileStore.swift`, `Model/` (Profile, ProfileStep, ProfileValidation, ActionIdentifier, AutoExit), and `Tests/ModeKitTests/Support/`.
Do not start until you have read them. If anything here contradicts the docs beyond the items listed under "Decisions already made", stop and report it.

## Objective
Build the session controller of ModeKit: the action contract, the `SessionController` actor with its state machine, rollback of a failed activation, conditional restore, crash recovery at launch, a degraded state with retry, and the auto-exit timer, all against fakes. Harden the durability of the file store that holds `session.json`. After this branch the four concrete actions (next two branches) only implement the contract; no controller change is needed to add them. Foundation only. No UI, no platform code, no concrete actions.

## Decisions already made (record them in the docs; do not re-decide)
1. Apply order. Steps are applied in the profile's array order and restored in the reverse order. Resolve the conflict by changing `docs/00-product-brief.md` ("applied in a fixed order" becomes "applied in the profile's step order and restored in reverse") and keep `docs/01-architecture.md`. Record as ADR-031.
2. The contract is split so that recovery works without the profile (the profile may have been edited or deleted since the crash):
```swift
public enum RestoreOutcome: Equatable, Sendable { case restored, skippedBecauseChangedByUser }

public protocol ActionRestorer: Sendable {
    associatedtype Snapshot: Codable & Sendable
    associatedtype AppliedState: Codable & Sendable
    var identifier: ActionIdentifier { get }
    /// `applied` is nil when the apply was interrupted (crash, or a failure while applying this action):
    /// the system may be partly changed and the applied value is unknown. Then restore unconditionally to `snapshot`.
    func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome
}

public protocol ModeAction: ActionRestorer {
    func capture() async throws -> Snapshot
    func apply() async throws -> AppliedState
}

public protocol ActionFactory: Sendable {
    func makeAction(for step: ProfileStep) throws -> any ModeAction
    func makeRestorer(for identifier: ActionIdentifier) throws -> any ActionRestorer
}
```
   `AnyModeAction` and an equivalent restorer wrapper stay internal: they open the existentials, encode `Snapshot` and `AppliedState` to `Data` with the encoder/decoder in `PersistenceCoding`, and decode them back. Rules stay as in docs/01 (capture reads only; apply idempotent-safe; restore conditional per ADR-008; one action failing never blocks the others). Record the `applied: nil` semantics and the split as ADR-032, with the consequence stated: after a crash, an interrupted action is restored to its snapshot even if the user changed the value in the meantime, because leaving the system in a half-applied state is worse.
3. New ports in `Ports/`, both Foundation only:
   - `SessionClock: Sendable` with `now() -> Date` and `sleep(for: Duration) async throws`. Name it `SessionClock`, not `Clock`, because `Clock` would shadow the standard library protocol; fix the name in docs/01 and docs/06. Real implementation `SystemSessionClock` in `Ports/` or `Session/` (ContinuousClock for sleep, `Date()` for now). Test fake `FakeClock` with `advance(by:)` that resumes sleepers whose deadline has passed, deterministic, no real time.
   - `SessionLogger: Sendable` with `log(_ event: SessionEvent)`. `SessionEvent` is a typed enum: state transition (from, to, session ID), ignored trigger (reason, state), action step results (captured, applied, restored, skipped, failed, with identifier and reason), recovery start and result. The controller never imports `os`. The real implementation (`os.Logger`, privacy annotations) arrives with the Platform adapters in M2. Reasons may contain paths: document that implementations must treat them as private. Test fake `RecordingSessionLogger`.
4. Public API (exact names; add nothing else public):
```swift
public actor SessionController {
    public init(actionFactory: any ActionFactory, sessionStore: SessionStore,
                clock: any SessionClock, logger: any SessionLogger)
    public var state: SessionState { get }
    public func stateUpdates() -> AsyncStream<SessionState>        // yields the current state first, then every change
    public func recoverIfNeeded() async -> RecoveryOutcome
    public func activate(_ profile: Profile) async throws(SessionError) -> TriggerResult<ActiveSession>
    public func deactivate() async throws(SessionError) -> TriggerResult<RestoreReport>
    public func retryRestore() async -> TriggerResult<RecoveryOutcome>
    public func discardUnreadableSession() async throws(SessionError) -> TriggerResult<Void>
}
```
   Supporting public types, each `Equatable` and `Sendable`:
   - `SessionState`: `idle`, `applying(sessionID:profileName:)`, `active(ActiveSession)`, `restoring(sessionID:profileName:)`, `rollingBack(sessionID:profileName:)`, `degraded(DegradedReason)`.
   - `ActiveSession { sessionID, profileID, profileName, startedAt }`.
   - `DegradedReason`: `restoreFailed(sessionID:profileName:failures:[ActionFailure])`, `unreadableSessionFile(StoreError)`.
   - `ActionFailure { identifier: ActionIdentifier, reason: String }`. `reason` is `String(describing: error)`, a non-localized diagnostic; the UI maps by identifier and phase.
   - `RestoreReport { restored, skippedBecauseChangedByUser: [ActionIdentifier], failed: [ActionFailure] }`.
   - `RecoveryOutcome`: `nothingToRecover`, `restored(RestoreReport)`, `partiallyRestored(RestoreReport)`, `blocked(StoreError)`, `alreadyAttempted`.
   - `TriggerResult<Value: Sendable>`: `performed(Value)`, `ignored(currentState: SessionState)`.
   - `SessionError` (typed, with associated values): `invalidProfile(ProfileValidationError)`, `recoveryNotRun`, `captureFailed(ActionFailure)`, `sessionStoreFailed(StoreError)`, `applyFailed(ActionFailure, rollback: RestoreReport)`.
   - `ActionError`: `unsupported(ActionIdentifier)`, `undecodableRecord(ActionIdentifier, reason: String)`.
5. Behavior, exactly:
   - Initial state `idle`, with recovery not yet run. `activate` before `recoverIfNeeded()` has run throws `recoveryNotRun`.
   - Reentrancy (the actor is reentrant at every `await`): each public method reads the state and, if it applies, sets the new state before its first suspension. `activate` is `performed` only from `idle`; `deactivate` only from `active`; `retryRestore` only from `degraded`; `discardUnreadableSession` only from `degraded(.unreadableSessionFile)`. Any other call returns `ignored(currentState:)`, is logged, and is never queued. Switching profiles is not a v1 flow: activate while active is ignored.
   - Activate: validate the profile with `ProfileValidation` (`invalidProfile`, nothing touched) -> build actions via the factory -> `applying` -> capture every action in profile order (a capture failure throws `captureFailed`; nothing was applied and no file was written; state back to `idle`) -> write `session.json` with `appliedData` nil for all records, before the first apply (a store failure throws `sessionStoreFailed`, nothing applied, `idle`) -> apply each action in profile order, and after each success persist the record with its `appliedData` -> `active`; start the auto-exit timer when `profile.autoExit` is non-nil. An empty profile activates with zero records.
   - Apply failure at step N (the action throws, or persisting its applied record fails): `rollingBack`; restore the already applied actions in reverse using the in-memory records, and action N itself with `applied: nil` (it may be partly applied; when the failure was only the persistence of its record, use its in-memory applied state). Rollback restores are conditional like any restore. If every rollback restore succeeded or was skipped: remove `session.json` (`clearSession`), state `idle`, throw `applyFailed(failure, rollback:)`. If a rollback restore failed: rewrite `session.json` with only the failed records, state `degraded(.restoreFailed)`, throw `applyFailed` with the failures in `rollback`. A failure to remove or rewrite the file during rollback is logged and does not replace the `applyFailed` error.
   - Deactivate, and the timer: `restoring`; restore every record in reverse order, one failing never stops the others, a record with nil `appliedData` restores with `applied: nil`. All restored or skipped: remove `session.json`, `idle`, return the report. Any failure: rewrite `session.json` with only the failed records, `degraded(.restoreFailed)`, return the report (failures are in the report; per-action failures do not throw). If removing the file fails after a fully successful restore, state `idle`, throw `sessionStoreFailed`: the stale file is harmless because the next activation overwrites it and a recovery would restore conditionally.
   - Timer: a retained `Task` that sleeps on the injected `SessionClock` and then calls the same deactivate path. It is cancelled by every deactivate, by rollback and by recovery, and a fired timer acts only if the state is still `active` with the same session ID (stale timers do nothing).
   - Recovery (`recoverIfNeeded`): runs once, before any activation; later calls return `alreadyAttempted`. `loadSession`; nil -> `nothingToRecover`. A `StoreError` (corrupted or newer schema) -> the file is not touched, state `degraded(.unreadableSessionFile(error))`, return `blocked`. A readable record -> `restoring`, restore in reverse using `makeRestorer(for:)` and the record only (never the profile), same outcome rules as deactivate. No timer after recovery. A record that cannot be decoded or has no registered restorer is a restore failure for that action (`ActionError`), kept in the file.
   - `retryRestore`: from `degraded`, reload `session.json` and run the same restore pass on what it holds (`unreadableSessionFile` may now be readable). `discardUnreadableSession` calls `clearSession`, then `idle`; it is the explicit user decision that unreadable data is abandoned.
   - Logging: one `SessionEvent` per state transition and per action step, with the session ID.
   - No watchdog: a hung action would hold the controller in `applying` or `restoring`. Timeouts belong to the adapters (docs/03). Do not add a controller-level timeout; list it under "Observed but not done".
6. Durability of `session.json` (ADR-033). Change `FileManagerFileStore` (all its callers benefit, including `profiles.json`): (a) flush the temporary file with `fcntl(fd, F_FULLFSYNC)`, falling back to `fsync` only when `F_FULLFSYNC` reports it is unsupported (`ENOTSUP`, `ENOTTY`); (b) after the `rename`, flush the parent directory the same way. A failure of the directory flush after a completed rename is best effort and must be documented with a justifying comment in the code, like the existing temporary-file cleanup. Document the cost (tens of milliseconds per write) and that the controller writes the session file once per action plus once at the start. Power-loss behavior cannot be tested here: say so in the report as unverified; keep every existing test passing.

## Scope (do exactly this)
Under `Packages/ModeKit/Sources/ModeKit/`: `Session/` for the contract, controller, state and report types (split into several files of at most 300 lines; keep the actor itself small by moving the capture/apply/restore passes into internal helper types with one job each), `Ports/` for `SessionClock` and `SessionLogger`. Tests under `Packages/ModeKit/Tests/ModeKitTests/` mirroring the source layout. Support code in `Tests/ModeKitTests/Support/`: `FakeModeAction` (scripted capture, apply, restore outcomes and failures; optional gate to suspend inside a call; records calls into one shared ordered log so cross-action order is assertable), `FakeActionFactory`, `FakeClock`, `RecordingSessionLogger`, an `AsyncGate` for reentrancy tests. Fake actions use a small `Codable` test snapshot and applied state.

## Out of scope (do not do)
- Any concrete action (`desktopIcons`, `dock`, `menuBar`, `hideApps`, `wallpaper`), the Focus step, `DefaultsStore`, `ProcessRunner`, `AppleScriptRunner`, `WorkspaceAdapter`, `DistributedNotifier` (later branches).
- Anything in `App/`, any UI, any Platform adapter, the `os.Logger` implementation of `SessionLogger`.
- Switching profiles while active, queued triggers, a controller watchdog, profile CRUD.
- Changing the file formats. `SessionRecord` and `ActionRecord` stay as merged; only their documented semantics (`appliedData` nil) are used.

## Requirements
- Architecture: ModeKit imports Foundation only. `git grep -nE "^import " Packages/ModeKit/Sources | grep -v "import Foundation"` must print nothing. No third-party packages.
- Code: follow docs/03-code-standards.md. No TODOs, no stubs, no commented-out code, no unrequested abstractions, no `Utils`/`Helpers`/`Manager` names, no boolean parameters, no force unwraps, no `try?` that discards a failure without a justifying comment, no `print`. Files at most 300 lines, functions at most 50. Public API documented with `///` (behavior, errors, threading, reentrancy).
- Concurrency: Swift 6 strict concurrency, zero warnings. All state in the actor. Models and reports are value types. No `DispatchQueue`, no locks in ModeKit sources.
- Typed throws for `SessionError` where the compiler allows it, consistent with existing code.
- Names: use exactly the type names above; vocabulary is profile, session, snapshot, action, step.
- Edge cases to handle explicitly: empty profile; single step; all steps; duplicate steps (rejected by validation before anything is touched); capture failure at the first, a middle and the last action; session write failure before the first apply; record persistence failure after an apply; apply failure at the first, a middle and the last step; rollback restore failing for one action; restore failing for one action and a later retry succeeding; restore skipped because the user changed the value; snapshot data that cannot be decoded at recovery; action identifier with no restorer at recovery; recovery with a corrupted file, a newer-schema file and a valid file whose profile no longer exists; recovery with `appliedData` nil on some records; second trigger during applying, restoring and rolling back; timer firing while the user deactivates (stale timer); timer cancelled by deactivate; `deactivate` and `activate` from the wrong states; `activate` before recovery; `stateUpdates` delivering the full sequence to a subscriber that started before `activate`.

## Acceptance criteria
- [ ] `make verify` passes with zero warnings; `swift test --package-path Packages/ModeKit` passes.
- [ ] Every mandatory scenario 1 to 10 in docs/06-testing.md has at least one test, named after the behavior. The report maps each scenario number to its test names.
- [ ] A test proves `session.json` exists and lists all actions before the first `apply` call (read the in-memory file store from inside the fake action's apply).
- [ ] A test proves that two triggers racing across an `await` result in one transition and one `ignored` (use `AsyncGate`; no sleeps, no real time).
- [ ] No test uses real time or real file system, except the existing `FileManagerFileStore` integration tests.
- [ ] Import grep above is empty.
- [ ] Coverage of the new ModeKit code is at least 90% with meaningful assertions (report the number and how you measured it).
- [ ] The docs listed below match the code.

## Test plan
- Automated (Swift Testing): all scenarios from docs/06 and the edge cases above, against `FakeActionFactory`, `FakeClock`, `RecordingSessionLogger` and `InMemoryFileStore` through the real `SessionStore`. Assert state sequences from `stateUpdates()`, the ordered call log, the logged events, and the final contents of the session file. Add `FileManagerFileStore` tests that the new flush path still writes, replaces and cleans up as before, including a write into a fresh directory.
- Commands: `make verify`.
- Manual QA: none applies (no platform code). State that in the report.

## Git instructions
- Start from an up-to-date main: `git fetch origin --prune; git switch main; git pull --ff-only`.
- This prompt file is untracked in the working tree. Create branch `feat/modekit-session-controller`, then make this file the first commit: `docs(prompts): add M1 session controller prompt`.
- Then commit atomically with Conventional Commits, tests in the same commit as the code they cover, every commit passing `make verify`. Suggested order: contract, ports and test fakes; state, error and report types with activate, rollback and deactivate and the timer; recovery, retry and discard; durability of `FileManagerFileStore`; docs. Scope `session` for every code commit, `docs` for the docs commit.
- Stage files explicitly (never `git add .` or `-A`). Read `git diff --cached` before each commit. Never `--no-verify`.
- Push the branch and open a PR titled "feat(session): add session controller" using `.github/pull_request_template.md`. Do not merge.

## Docs to update in the same branch
- `docs/00-product-brief.md`: apply order sentence (decision 1).
- `docs/01-architecture.md`: the action contract (split, `RestoreOutcome`, `applied: nil`), the state machine diagram with `degraded` reasons and rollback failure, the controller section (activation order with per-action persistence, recovery, retry, discard, timer), the port table (`SessionClock`, `SessionLogger`; fix the `Clock` name), the error types.
- `docs/06-testing.md`: `SessionClock` naming, the new fakes, the added scenarios (activate before recovery, interrupted apply at recovery, stale timer); note that after an interrupted restore a later `skippedBecauseChangedByUser` can also mean "already restored".
- `docs/09-decisions.md`: ADR-031 apply order, ADR-032 contract split and `applied: nil` semantics (with `SessionClock`/`SessionLogger` naming and the no-watchdog decision), ADR-033 durability of file writes. Each: context, decision, consequence, "proposed by the assistant; user to confirm".
- `docs/12-data-formats.md`: `appliedData` nil semantics, the session file contents during rollback and degraded states (only failed records remain), the durability note.
- `docs/02-project-structure.md`: new files.
- `docs/STATUS.md`: second M1 branch done, next branch `feat/modekit-actions-desktop-icons-dock`, the resolved apply-order conflict removed from the open items, new open items.

## Report format
Branch, Commits, Files changed, make verify result (test counts, coverage and how measured), scenario-to-test map for 1 to 10, Manual QA, Docs updated, Observed but not done (include the missing controller watchdog), Unverified (include `F_FULLFSYNC` under power loss, `ContinuousClock` across system sleep, macOS 14 and 15), Next step (see docs/10-claude-code-protocol.md).
