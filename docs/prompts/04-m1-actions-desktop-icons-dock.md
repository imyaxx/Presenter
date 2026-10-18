You are a senior macOS and Swift engineer with more than 15 years of experience shipping production software. You write clean, stable, readable code with precise names and clear architecture. You do not write demo-quality or "vibe" code. You verify your work before declaring it done. You never state a platform fact you have not observed. You are working in an existing repository with strict rules.

## Context to read first (mandatory, in order)
1. CLAUDE.md
2. docs/STATUS.md
3. docs/README.md, then: docs/01-architecture.md (action contract, action mechanisms table, session controller, system ports), docs/02-project-structure.md, docs/03-code-standards.md (all of it; limits are enforced), docs/06-testing.md (per-action scenarios, fakes), docs/07-macos-integration.md (the Desktop icons and Dock sections and the spike log entries S5 and S4: these are the only evidence for the mechanisms), docs/09-decisions.md (ADR-008, 010, 025, 028, 029, 030, 032, 033), docs/05-git-workflow.md, docs/10-claude-code-protocol.md
4. Packages/ModeKit as merged: `Session/` (`ModeAction`, `ActionRestorer`, `ActionFactory`, `RestoreOutcome`, `AnyModeAction`, `SessionController`), `Ports/`, `Model/ProfileStep.swift`, `Model/ActionIdentifier.swift`, `Tests/ModeKitTests/Support/` (`FakeModeAction`, `SessionControllerHarness`, `InMemoryFileStore`).
Do not start until you have read them. If anything here contradicts the docs beyond the items under "Decisions already made", stop and report it.

## Objective
Implement the first two concrete actions of ModeKit, `desktopIcons` and `dock`, against new system ports, with a `StandardActionFactory` that the app will use, and prove with end-to-end ModeKit tests (real `SessionController`, real `SessionStore`, stateful fakes) that a session over these two actions restores the system exactly, including crash recovery. The session controller and the file formats do not change. No real adapters: the Platform implementations arrive in M2. Foundation only.

## Decisions already made (record them in the docs; do not re-decide)
1. Ports, all in `Ports/`, `Sendable`, Foundation only, documented with `///`:
```swift
public enum DefaultsValue: Hashable, Sendable { case bool(Bool), integer(Int) }   // Codable with an explicit "type" discriminator (ADR-030), like the other enums with fields
public struct DefaultsKey: Hashable, Sendable { public let domain: String; public let name: String }
public protocol DefaultsStore: Sendable {
    func value(for key: DefaultsKey) async throws -> DefaultsValue?   // nil = the key is absent (not the same as false)
    func set(_ value: DefaultsValue, for key: DefaultsKey) async throws
    func remove(_ key: DefaultsKey) async throws                      // succeeds when absent
}

public struct ProcessCommand: Hashable, Sendable { public let executableURL: URL; public let arguments: [String]; public let timeout: Duration }
public struct ProcessResult: Equatable, Sendable { public let exitCode: Int32 }
public protocol ProcessRunner: Sendable {
    func run(_ command: ProcessCommand) async throws -> ProcessResult  // argv array only, never a shell string; a nonzero exit is a result, not an error
}

public struct AppleScript: Hashable, Sendable { public let source: String; public init(_ source: StaticString) }
public protocol AppleScriptRunner: Sendable {
    func run(_ script: AppleScript, timeout: Duration) async throws    // the script result is not needed by any action
}
```
   `AppleScript` takes a `StaticString` so a script can only be a compile-time literal: no interpolation, no injection (this replaces the allowlist idea for these two actions; document it). Typed errors with `CustomStringConvertible` diagnostics: `DefaultsError` (`unsupportedValueType(key)`, `failed(reason)`), `ProcessError` (`timedOut(Duration)`, `launchFailed(reason)`), `AppleScriptError` (`notAuthorized` for -1743, `timedOut` for -1712, `failed(code: Int, message: String)`). The adapters (M2) enforce the timeouts and map errors. `DefaultsStore` is local preference access and has no timeout by design, like `FileStore` (state this). Do not add a stdout field, a domain enum or any port member no action in this branch uses.
2. Desktop icons action (`DesktopIconsAction`, identifier `.desktopIcons`; mechanism from ADR-028 and S5). Key `DefaultsKey(domain: "com.apple.finder", name: "CreateDesktop")`.
   - Snapshot `{ createDesktop: DefaultsValue? }`, applied state `{ createDesktop: DefaultsValue }`.
   - `capture`: read the key only.
   - `apply`: if the current value already equals `.bool(false)`, do nothing (no write, no Finder restart) and return it as applied state. Otherwise `set(.bool(false))`, then run `/usr/bin/killall Finder`, return `.bool(false)`.
   - `restore(snapshot, expecting applied)`: read the current value. If `applied` is non-nil and the current value differs, return `.skippedBecauseChangedByUser` (no write, no restart). Otherwise, if the current value already equals the snapshot (absent equals absent), return `.restored` with no write and no restart. Otherwise write the snapshot value, or `remove` the key when the snapshot is absent (never write a default for an absent key), then run `killall Finder`, return `.restored`. The captured value keeps its type (an integer stays an integer).
   - `killall` exit code: 0 is success; 1 means no matching process (Finder not running), which is treated as success because there is nothing to restart and launchd brings Finder back; any other code, or a thrown `ProcessError`, is a failure of the action. Before relying on exit 1, read the local `man killall` and quote what it says in the code comment; mark in the docs that the exit-1 behavior was not observed on a running system.
   - Timeout for the `killall` command: 10 seconds.
3. Dock action (`DockAction`, identifier `.dock`; mechanism from ADR-025 and S4). Key `DefaultsKey(domain: "com.apple.dock", name: "autohide")`. Scripts (compile-time literals): `tell application "System Events" to set autohide of dock preferences to true` and the same with `false`.
   - Snapshot `{ autohide: DefaultsValue? }`, applied state `{ autohide: DefaultsValue }`.
   - `capture`: read the key only through `DefaultsStore`; capture never calls AppleScript, so it can never raise the Automation prompt.
   - `apply`: if the current value already equals `.bool(true)`, do nothing and return it. Otherwise run the `true` script, then read the key back; if it is not `.bool(true)`, throw `DockActionError.settingNotApplied(observed: DefaultsValue?)` (a typed error with a diagnostic; the mechanism did not take effect). Return the value read back.
   - `restore(snapshot, expecting applied)`: read the current value. `applied` non-nil and different: `.skippedBecauseChangedByUser`. Otherwise, target = the snapshot truthiness (`.bool(true)` is auto-hide on, absent or anything else is off). If the effective state differs from the target, run the matching script. Then make the key equal to the snapshot exactly: snapshot absent and the key present, `remove` it; snapshot present and the key differs, `set` it. No `killall Dock` anywhere (ADR-025: no silent fallback). Return `.restored`.
   - Timeout for the script: 130 seconds, deliberately above the system's 120 s unanswered-prompt limit (S4) so the adapter reports `AppleScriptError.timedOut` from the system and not a premature local timeout. Document the consequence: while the first-run Automation prompt is unanswered, a session stays in `applying` for up to about two minutes; onboarding (M4) requests the permission ahead of time. Authorization denied (`notAuthorized`) on apply rolls back the activation; on restore it makes that action a restore failure and the session `degraded`. Both are covered by tests.
4. `StandardActionFactory: ActionFactory` takes the three ports in `init`. `makeAction(for:)` maps `.hideDesktopIcons` and `.hideDock`; every other step throws `ActionError.unsupported(identifier)` (those actions arrive in the next branch, which extends this factory). `makeRestorer(for:)` returns the same action types for `.desktopIcons` and `.dock`, `ActionError.unsupported` otherwise. The actions are small `struct`s holding their ports, no shared mutable state.
5. Skip-when-equal (no needless Finder restart or Automation call) and the `killall` exit-1 rule are recorded as ADR-035. The port shapes, the `StaticString` rule and the timeouts-at-the-adapter rule are ADR-034. Each: context, decision, consequence, "proposed by the assistant; user to confirm".
6. The Automation entitlement and `NSAppleEventsUsageDescription` (ADR-025: "added in the milestone that implements the action") are added by the M2 branch `feat/platform-adapters`, the first one with a real `AppleScriptRunner`. This branch touches nothing under `App/`. Record that requirement, with the English and Russian usage description, in `docs/STATUS.md` as an M2 item.

## Scope (do exactly this)
Sources under `Packages/ModeKit/Sources/ModeKit/`: ports and their types in `Ports/`, the actions and the factory in a new `Actions/` folder (one file per type, files at most 300 lines), add the folder to docs/02. Tests under `Packages/ModeKit/Tests/ModeKitTests/` mirroring the layout. Support code in `Tests/ModeKitTests/Support/`:
- `FakeDefaultsStore`: in-memory, failure injection per operation, an ordered call log of reads, writes and removes, and a way to compare the whole stored state before and after a session.
- `FakeProcessRunner`: records commands, scripted result or error per command, optional hook.
- `FakeAppleScriptRunner`: records scripts, scripted result or error. When given a `FakeDefaultsStore`, it models System Events as observed in S4: the `true` script writes `.bool(true)` and the `false` script writes `.bool(false)` to `com.apple.dock autohide` (an explicit key, never a delete). Document in the fake that this models S4.
No mocks of the units under test.

## Out of scope (do not do)
- The actions `hideApps`, `wallpaper`, `menuBar`, Focus, and the ports `WorkspaceAdapter`, `DistributedNotifier` (next branch). Any real adapter, `Platform/`, `App/`, UI, entitlements, `Info.plist` or localization.
- Any change to `SessionController`, `SessionStore`, the file formats or `ProfileStep`. If an end-to-end test shows that a controller change is needed, stop and report; do not change it.
- A controller-level watchdog, `killall Dock`, a `defaults`-CLI fallback.

## Requirements
- Architecture: ModeKit imports Foundation only. `git grep -nE "^import " Packages/ModeKit/Sources | grep -v "import Foundation"` must print nothing. No third-party packages.
- Code: follow docs/03-code-standards.md. No TODOs, no stubs, no commented-out code, no unrequested abstractions, no `Utils`/`Helpers`/`Manager` names, no boolean parameters, no force unwraps, no `try?` that discards a failure without a justifying comment, no `print`. Files at most 300 lines, functions at most 50. Public API documented with `///` (behavior, errors, threading).
- Concurrency: Swift 6 strict concurrency, zero warnings. Actions and fakes are `Sendable`.
- Names: use exactly the names above; vocabulary is profile, session, snapshot, action, step.
- Edge cases to handle explicitly, each with a test: desktop icons: key absent, `false`, `true`, stored as an integer; icons already hidden; Finder not running (exit 1); `killall` fails (exit 2, `ProcessError.timedOut`, launch failure); write failure; restore skipped because the user changed the value; restore with `applied: nil`; the key absent at capture is deleted on restore, never written. Dock: key absent, `true`, `false`; already auto-hidden (no script run on apply, none on restore); `notAuthorized` and `timedOut` on apply and on restore; script succeeds but the key does not read back as `true`; key absent at capture restores to absent after the script wrote an explicit `false` (S4); restore skipped because the user changed autohide; restore with `applied: nil`; defaults read failure.
- Not in scope for UI, so no L10n and no tokens.

## Acceptance criteria
- [ ] `make verify` passes with zero warnings; `swift test --package-path Packages/ModeKit` passes.
- [ ] For each action, tests cover every item of the per-action scenario list in docs/06 that applies to it (capture reads current state; apply sets the expected state; restore returns to the captured state; restore skips when changed; state already equal to the target; the system call fails; timeout). The report maps each item to test names.
- [ ] End-to-end tests with `SessionController`, `StandardActionFactory`, `SessionStore` over `InMemoryFileStore`, and the stateful fakes: (a) activate a profile with both steps then deactivate: the `FakeDefaultsStore` state is identical to the initial state, for three initial states (both keys absent; both present; icons hidden and Dock auto-hidden already) and the process and script call logs show no needless calls; (b) activation fails at the second step (Dock `notAuthorized`): the first step is rolled back, the defaults state equals the initial state, no session file remains; (c) crash recovery: persist a session after a full activation, build a new controller and factory, `recoverIfNeeded` restores the initial state from the session file alone; (d) the user changes the Dock key during the session, deactivate leaves it and reports `skippedBecauseChangedByUser` for `.dock` only.
- [ ] `git diff main -- Packages/ModeKit/Sources/ModeKit/Session Packages/ModeKit/Sources/ModeKit/Persistence` is empty.
- [ ] Import grep above is empty.
- [ ] Coverage of the new ModeKit code is at least 90% with meaningful assertions (report the number and how you measured it).
- [ ] The docs listed below match the code.

## Test plan
- Automated (Swift Testing): per-action unit tests against the three fakes, the end-to-end tests above, error mapping and diagnostics of the three typed errors, `DefaultsValue` coding round trip with the `type` discriminator, `StandardActionFactory` (supported and unsupported steps and identifiers). No real time, no real file system, no real process.
- Commands: `make verify`.
- Manual QA: none applies, there are no real adapters yet. State that in the report, and list under "Unverified" that the mechanisms were verified in M0 (S4, S5) through scripts, not yet through ModeKit.

## Git instructions
- Start from an up-to-date main: `git fetch origin --prune; git switch main; git pull --ff-only`.
- This prompt file is untracked in the working tree. Create branch `feat/modekit-actions-desktop-icons-dock`, then make this file the first commit: `docs(prompts): add M1 desktop icons and Dock actions prompt`.
- Then commit atomically with Conventional Commits, tests in the same commit as the code they cover, every commit passing `make verify`. Suggested order: ports, typed errors and fakes; `DesktopIconsAction`; `DockAction`; `StandardActionFactory` and the end-to-end tests; docs. Scopes: `icons` for the desktop icons commit, `dock` for the Dock commit, `session` for ports, factory and end-to-end tests, `docs` for the docs commit.
- Stage files explicitly (never `git add .` or `-A`). Read `git diff --cached` before each commit. Never `--no-verify`.
- Push the branch and open a PR titled "feat(icons): add desktop icons and Dock actions" using `.github/pull_request_template.md`. Do not merge.

## Docs to update in the same branch
- `docs/01-architecture.md`: the ports table (`DefaultsStore`, `ProcessRunner`, `AppleScriptRunner` now defined in ModeKit, implementations in M2), the action mechanisms table (state "implemented against ports"), the factory.
- `docs/06-testing.md`: the new fakes and the S4 model in `FakeAppleScriptRunner`.
- `docs/07-macos-integration.md`: in the Desktop icons and Dock sections, add one line each saying the action is implemented in ModeKit against ports and that the in-app `CFPreferences` access to the `com.apple.finder` and `com.apple.dock` domains is `UNVERIFIED` (S1 verified `CFPreferences` only for the Control Center and global domains); the M2 adapter branch must verify it or use the `defaults` tool through `ProcessRunner`. Also mark `killall` exit 1 as read from `man`, not observed.
- `docs/09-decisions.md`: ADR-034, ADR-035.
- `docs/02-project-structure.md`: `Actions/` and the new ports.
- `docs/STATUS.md`: third M1 branch done, next branch `feat/modekit-actions-apps-wallpaper-menubar`, the M2 requirement from decision 6, the unverified items.

## Report format
Branch, Commits, Files changed, make verify result (test counts, coverage and how measured), per-action scenario-to-test map, end-to-end tests (a to d), Manual QA, Docs updated, Observed but not done, Unverified (include in-app `CFPreferences` for the Finder and Dock domains, `killall` exit 1 on a running system, macOS 14 and 15, a second display is not relevant here), Next step (see docs/10-claude-code-protocol.md).
