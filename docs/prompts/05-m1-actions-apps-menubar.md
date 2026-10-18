You are a senior macOS and Swift engineer with more than 15 years of experience shipping production software. You write clean, stable, readable code with precise names and clear architecture. You do not write demo-quality or "vibe" code. You verify your work before declaring it done. You never state a platform fact you have not observed. You are working in an existing repository with strict rules.

## Context to read first (mandatory, in order)
1. CLAUDE.md
2. docs/STATUS.md
3. docs/README.md, then: docs/01-architecture.md (action contract, action mechanisms table, system ports), docs/02-project-structure.md, docs/03-code-standards.md (all of it; limits are enforced), docs/06-testing.md (per-action scenarios, fakes), docs/07-macos-integration.md (the Hide apps and Menu bar sections, and the spike log entry S1: the only evidence for the menu bar mechanism), docs/08-roadmap.md (M1), docs/09-decisions.md (ADR-008, 009, 023, 026, 029, 030, 032, 034, 035), docs/05-git-workflow.md, docs/10-claude-code-protocol.md
4. Packages/ModeKit as merged: `Actions/` (`DesktopIconsAction`, `DockAction`, `StandardActionFactory`), `Ports/` (`DefaultsStore`, `DefaultsValue`, `DefaultsKey`, `ProcessRunner`, `AppleScriptRunner` and their errors), `Session/` (`ModeAction`, `ActionRestorer`, `RestoreOutcome`), `Model/ProfileStep.swift`, `Model/BundleIdentifier.swift`, and in `Tests/ModeKitTests/Support/` the fakes and `StandardActionsHarness`; read how the existing two actions and their tests are written and follow the same style.
Do not start until you have read them. If anything here contradicts the docs beyond the items under "Decisions already made", stop and report it.

## Objective
Implement the `hideApps` and `menuBar` actions of ModeKit against ports, extend `StandardActionFactory` to build them, and prove with end-to-end tests (real `SessionController`, `SessionStore`, stateful fakes) that a session over desktop icons, Dock, menu bar and hide apps restores the system exactly, including crash recovery. The session controller and file formats do not change. No real adapters (M2). Foundation only. The wallpaper action is deliberately not in this branch: it is the riskiest action (undocumented store file, polling for the agent) and gets its own branch after this one, `feat/modekit-action-wallpaper`.

## Decisions already made (record them in the docs; do not re-decide)
1. Roadmap change. Replace the last M1 branch `feat/modekit-actions-apps-wallpaper-menubar` in `docs/08-roadmap.md` and `docs/STATUS.md` with two sequential branches: `feat/modekit-actions-apps-menubar` (this one) and `feat/modekit-action-wallpaper`.
2. New ports in `Ports/`, `Sendable`, Foundation only, documented with `///`:
```swift
public struct RunningApplication: Hashable, Sendable {
    public let bundleIdentifier: BundleIdentifier
    public let isHidden: Bool
    public let isFrontmost: Bool
    public let isThisApplication: Bool
}
public enum ApplicationVisibilityChange: Equatable, Sendable { case changed, notRunning, refused }

public protocol WorkspaceAdapter: Sendable {
    /// Regular (Dock-visible) applications only. The adapter skips applications whose bundle identifier is not a valid `BundleIdentifier`.
    func runningApplications() async -> [RunningApplication]
    func hide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange
    func unhide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange
}

public struct DistributedNotificationName: Hashable, Sendable { public let rawValue: String }   // with a static constant for the menu bar one
public protocol DistributedNotifier: Sendable { func post(_ name: DistributedNotificationName) async }
```
   `changed` means the request was accepted, not that the effect was observed: hiding is asynchronous in AppKit; say so in the docs. `WorkspaceAdapter` is meant to grow (displays, wallpaper) in the next branch; add only what these two actions use. The global preferences domain is the string `"NSGlobalDomain"` in a `DefaultsKey` (document that the adapter maps it). Both ports are in-process calls with no timeout by design, like `DefaultsStore`; the adapter must not block (document).
3. Hide apps (`HideAppsAction`, identifier `.hideApps`, built from `ProfileStep.hideApps(exclusions:)`; ADR-009). The restore logic lives in a small `HideAppsRestorer` struct that `HideAppsAction` uses for its `restore`, so recovery can build it from an identifier alone (the exclusions are not needed to restore). `makeRestorer(for: .hideApps)` returns the restorer.
   - Candidates = running applications with `isHidden == false`, not `isThisApplication`, not `isFrontmost`, whose bundle identifier is not in the exclusions. Applications already hidden before activation are never touched and stay hidden after (ADR-009).
   - Snapshot `{ candidates: [BundleIdentifier] }`, sorted by raw value for determinism. Applied state `{ hidden: [BundleIdentifier] }`, the candidates whose `hide` returned `.changed`, in the same order.
   - `capture`: list and filter, read only. `apply`: hide each candidate; `.notRunning` and `.refused` are skipped silently (an application that refuses or quit is not an error; this is recorded as "not reported to the user yet" under "Observed but not done"); never fails because of an application. Return the hidden list (possibly empty).
   - `restore(snapshot, expecting applied)`: the set to unhide is `applied.hidden` when `applied` is non-nil, else `snapshot.candidates` (interrupted apply). List the running applications once. For each id in the set: not running, nothing to do (a closed application is never relaunched); running and visible, the user unhid it (or the system did when the user switched to it), leave it alone; running and hidden, call `unhide`. A `.refused` from `unhide` is a failure: attempt all the others first, then throw `HideAppsActionError.couldNotUnhide([BundleIdentifier])` (typed, with a diagnostic), so the session becomes `degraded` and a retry is possible. Outcome when nothing threw: `.skippedBecauseChangedByUser` if the set is non-empty, no application was unhidden by this call, and at least one was found running and visible; otherwise `.restored`.
   - Ordering: apply in snapshot order; restore in the same order (applications are independent).
4. Menu bar (`MenuBarAction`, identifier `.menuBar`; ADR-026 and S1). Keys: `DefaultsKey("com.apple.controlcenter", "AutoHideMenuBarOption")` (integer), `DefaultsKey("NSGlobalDomain", "_HIHideMenuBar")` (bool), `DefaultsKey("NSGlobalDomain", "AppleMenuBarVisibleInFullscreen")` (bool). The "Always" row of the S1 table is the target: `0`, `true`, `false`. Notification: `AppleInterfaceMenuBarHidingChangedNotification`.
   - Snapshot `{ autoHideOption, hideMenuBar, visibleInFullscreen: DefaultsValue? }`, applied state the three target values.
   - `capture`: read the three keys only. `apply`: if all three already equal the target, do nothing (no write, no notification) and return the target. Otherwise write the three keys in the order above, then post the notification once, return the target. A failing write stops the apply with the error (the controller rolls back with `applied: nil`).
   - `restore(snapshot, expecting applied)`: read the three keys. `applied` non-nil and any key differs: `.skippedBecauseChangedByUser` (the user changed the setting; System Settings writes all three keys). Otherwise, if all three already equal the snapshot (absent equals absent), return `.restored` with no write and no notification. Otherwise, for each key: write the captured value, or `remove` it when it was absent (never write a default for an absent key; S1 showed the UI writes explicit values and absent keys behave differently), then post the notification once. All three keys are always handled together. A failing write or remove does not stop the other keys; after attempting all, throw the first error.
   - Document the consequence (ADR-023, ADR-026): the notification name is undocumented; `post` cannot report whether macOS reacted, so the action cannot verify the live effect; the three keys are verified by reading them back in tests only.
5. `StandardActionFactory` gains `workspace: any WorkspaceAdapter` and `notifier: any DistributedNotifier` in its `init` (keep one parameter per line) and builds the two new actions and restorers. The wallpaper step still throws `ActionError.unsupported`. Update the harness and every caller.
6. ADRs: ADR-036 "Hide apps: ports and semantics" (the `WorkspaceAdapter` and `DistributedNotifier` shapes, candidates, snapshot and applied state, the outcome rule, refused and not-running handling, `changed` means accepted). ADR-037 "Menu bar action: three keys, skip-when-equal, notification" (decision 4 and its consequence). Each: context, decision, consequence, "proposed by the assistant; user to confirm".

## Scope (do exactly this)
Sources: ports in `Ports/`, `HideAppsAction`, `HideAppsRestorer`, `HideAppsActionError`, `MenuBarAction` in `Actions/` (one file per type, files at most 300 lines), the factory change. Tests mirror the layout. Support code in `Tests/ModeKitTests/Support/`:
- `FakeWorkspaceAdapter`: stateful list of running applications with visibility and frontmost flags; `hide` and `unhide` mutate it; scripted refusal per application; helpers to simulate the world changing during a session: `userUnhides`, `quit`, `launch`, `activate` (an application activated by the user becomes visible); an ordered log of calls.
- `FakeDistributedNotifier`: records posts in order.
- Extend `StandardActionsHarness` with the two fakes and a four-step profile (desktop icons, Dock, menu bar, hide apps).
No mocks of the units under test.

## Out of scope (do not do)
- The wallpaper action, `SolidColorImageRenderer`, display and wallpaper members of `WorkspaceAdapter`, Focus.
- Any real adapter, `Platform/`, `App/`, UI, entitlements, localization.
- Any change to `SessionController`, `SessionStore`, the file formats or `ProfileStep`. If an end-to-end test shows a controller change is needed, stop and report; do not change it.
- Reporting skipped or refused applications to the user (no channel exists yet), a controller watchdog.

## Requirements
- Architecture: ModeKit imports Foundation only. `git grep -nE "^import " Packages/ModeKit/Sources | grep -v "import Foundation"` must print nothing. No third-party packages.
- Code: follow docs/03-code-standards.md and the style of the two existing actions. No TODOs, no stubs, no commented-out code, no unrequested abstractions, no `Utils`/`Helpers`/`Manager` names, no boolean parameters (including in tests), no force unwraps, no `try?` that discards a failure without a justifying comment, no `print`. Files at most 300 lines, functions at most 50. Public API documented with `///` (behavior, errors, threading).
- Concurrency: Swift 6 strict concurrency, zero warnings.
- Names: use exactly the names above; vocabulary is profile, session, snapshot, action, step.
- Edge cases, each with a test. Hide apps: no candidates; every running application excluded; the frontmost application is never hidden; this application is never hidden; applications already hidden before activation stay hidden after the session; an application refuses to hide (not in applied, session unaffected); an application quits between capture and apply (`.notRunning`); an application quits during the session (not relaunched, outcome `.restored`); the user unhides one application (left alone) and not the others (the others unhidden, outcome `.restored`); the user unhides all of them (outcome `.skippedBecauseChangedByUser`); an application launched during the session is untouched; unhide refused for one application (the others are still unhidden, then the typed error, and a retry through the controller succeeds once it is allowed); restore with `applied: nil` uses the snapshot; applications that became visible because the user switched to them. Menu bar: all three keys absent (S1 baseline); the explicit "Never" row (3, absent, true), the "On Desktop Only" row (1, true, true), the explicit "In Full Screen Only" row (2, false, false); already "Always" (no write, no notification, on apply and on restore); keys absent at capture are removed on restore, never written; the user changed the setting during the session (skipped, no write, no notification); a write fails in the middle of apply (error, controller rollback restores all three keys to the snapshot); a write fails during restore (the other keys are still restored, the first error is thrown); restore with `applied: nil`; exactly one notification per apply and per restore.
- Not in scope for UI, so no L10n and no tokens.

## Acceptance criteria
- [ ] `make verify` passes with zero warnings; `swift test --package-path Packages/ModeKit` passes.
- [ ] For each action, tests cover every item of the per-action scenario list in docs/06 that applies to it (capture reads current state; apply sets the expected state; restore returns to the captured state; restore skips when changed; state already equal to the target; the system call fails). The report maps each item to test names.
- [ ] End-to-end tests with `SessionController`, `StandardActionFactory`, `SessionStore` over `InMemoryFileStore` and the stateful fakes: (a) activate the four-step profile then deactivate: defaults state and application visibility are identical to the initial state, for three initial worlds (everything at factory state; menu bar keys written explicitly by System Settings, Dock auto-hide on, some applications already hidden; everything already at the target); (b) activation fails at the last step: all earlier steps are rolled back and the world equals the initial one, no session file remains; (c) crash recovery: persist a session after a full activation, build a new controller and factory, `recoverIfNeeded` restores everything from the session file alone, including the hidden applications; (d) the user changes the menu bar setting and unhides one application during the session: deactivate reports `.menuBar` as skipped and restores the rest.
- [ ] `git diff main -- Packages/ModeKit/Sources/ModeKit/Session Packages/ModeKit/Sources/ModeKit/Persistence` is empty.
- [ ] Import grep above is empty.
- [ ] Coverage of the new ModeKit code is at least 90% with meaningful assertions (report the number and how you measured it).
- [ ] The docs listed below match the code.

## Test plan
- Automated (Swift Testing): per-action unit tests against the fakes, the end-to-end tests above, `HideAppsActionError` diagnostics, `StandardActionFactory` (new steps and identifiers supported, wallpaper still unsupported). No real time, no real file system, no real process, no real application.
- Commands: `make verify`.
- Manual QA: none applies, there are no real adapters yet. State that in the report and list under "Unverified" that these two mechanisms have not run through ModeKit on a real system.

## Git instructions
- Start from an up-to-date main: `git fetch origin --prune; git switch main; git pull --ff-only`.
- This prompt file is untracked in the working tree. Create branch `feat/modekit-actions-apps-menubar`, then make this file the first commit: `docs(prompts): add M1 hide apps and menu bar actions prompt`.
- Then commit atomically with Conventional Commits, tests in the same commit as the code they cover, every commit passing `make verify`. Suggested order: ports and fakes; `HideAppsAction` and `HideAppsRestorer`; `MenuBarAction`; factory and end-to-end tests; docs. Scopes: `apps` for hide apps, `menubar` for the menu bar, `session` for ports, factory and end-to-end tests, `docs` for docs.
- Stage files explicitly (never `git add .` or `-A`). Read `git diff --cached` before each commit. Never `--no-verify`.
- Push the branch and open a PR titled "feat(apps): add hide apps and menu bar actions" using `.github/pull_request_template.md`. Do not merge.

## Docs to update in the same branch
- `docs/01-architecture.md`: ports table (`WorkspaceAdapter` and `DistributedNotifier` defined in ModeKit, implementations in M2), action mechanisms table (hide apps and menu bar implemented against ports), the factory.
- `docs/06-testing.md`: the two new fakes.
- `docs/07-macos-integration.md`: Hide apps and Menu bar sections: implemented in ModeKit against ports; `NSRunningApplication.hide()` effect, behavior with several instances of one bundle identifier, full-screen applications and the in-app `CFPreferences` access to `NSGlobalDomain` for these keys stay `UNVERIFIED` (S1 verified `CFPreferences` from a throwaway app for the three menu bar keys: say exactly that, and that the M2 adapter keeps that route).
- `docs/08-roadmap.md` and `docs/STATUS.md`: the split of the last M1 branch (decision 1), fourth M1 branch done, next branch `feat/modekit-action-wallpaper`, unverified items, M2 requirements unchanged.
- `docs/09-decisions.md`: ADR-036, ADR-037.
- `docs/02-project-structure.md`: new files.

## Report format
Branch, Commits, Files changed, make verify result (test counts, coverage and how measured), per-action scenario-to-test map, end-to-end tests (a to d), Manual QA, Docs updated, Observed but not done (include that refused or quit applications are not reported to the user), Unverified (include `NSRunningApplication.hide()` effect, several instances of one bundle identifier, full-screen applications, the menu bar notification effect, macOS 14 and 15), Next step (see docs/10-claude-code-protocol.md).
