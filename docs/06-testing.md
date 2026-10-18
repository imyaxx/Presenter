# Testing

Nothing is committed or pushed without passing tests. Tests are part of the feature, not a follow-up.

## Pyramid

| Level | Scope | Tool | Runs |
|---|---|---|---|
| Unit | ModeKit: models, actions with fake ports, session controller, persistence | Swift Testing (`import Testing`, Xcode 16+) via `swift test` | `make test`, CI |
| Unit | App view models with fake services | Swift Testing | `make test`, CI |
| Integration (automated) | Real file store in a temporary directory; real JSON round trips | Swift Testing | `make test`, CI |
| Manual system QA | Real macOS side effects (Finder, Dock, wallpaper, menu bar, hiding apps) | Checklists below | Before every commit that touches platform code or an action; before every release |

UI snapshot or UI-automation tests are not part of v1. Visual verification is manual with screenshots in both appearances.

## What every test must do

- Arrange / act / assert. One behavior per test. Names describe behavior, not methods.
- Test boundaries and failures, not only the happy path.
- Use fakes for ports (`FakeDefaultsStore`, `FakeProcessRunner`, `FakeWorkspaceAdapter`, `FakeClock` for `SessionClock`, `RecordingSessionLogger` for `SessionLogger`, `InMemoryFileStore`) from `Tests/ModeKitTests/Support`. Do not mock internals of the unit under test.
- Session controller support: `FakeModeAction` (scripted capture, apply and restore results, an optional `AsyncGate` that suspends inside one call, one shared ordered `FakeCallLog` across actions), `FakeActionFactory`, `AsyncGate` for reentrancy tests, and `SessionControllerHarness`, which wires them to the real `SessionStore` over `InMemoryFileStore`. Assert state sequences through `stateUpdates()`, the call log, the logged events and the final session file.
- Action support: `FakeDefaultsStore` (in-memory values with an ordered log of reads, writes and removes, per-operation failure injection, `values` to compare the whole state before and after, `place` for changes made by another process), `FakeProcessRunner` (records commands, scripted result or error per command, optional hook), `FakeAppleScriptRunner` (records scripts and timeouts, scripted error per script). Given a `FakeDefaultsStore`, `FakeAppleScriptRunner` models System Events as observed in spike S4: the `true` and `false` Dock scripts write an explicit `.bool` to `com.apple.dock autohide`, never a delete. `FakeWorkspaceAdapter` (stateful list of running applications with hidden and frontmost flags; `hide` and `unhide` change it; `refuse` and `quitBefore` script a response per application and operation; `userUnhides`, `activate`, `quit` and `launch` change the world as the user would; an ordered call log), `FakeDistributedNotifier` (records posts in order), `RunningApplication.fixture` (builds applications with a visibility and a role instead of boolean arguments). `FakeDefaultsStore.failNext` can target one key. Wallpaper: `FakeWallpaperStore` keeps a text model of the store in an `InMemoryFileStore` (one line per display plus a volatile `lastUse` line). The agent persists a change made by `FakeWorkspaceAdapter.setDesktopImage` only after a configurable number of store reads, or never, which drives the polling. `userSets` and `agentTouchesLastUse` change the store as the user or the agent would. It is a coarse model of spike S2, not evidence about the real `Index.plist` format. `FakeWallpaperStoreInspector` fingerprints that text without the `lastUse` line and rejects data without its header, or throws a scripted error. `FakeSolidColorImageRenderer` records colors and returns deterministic bytes or a scripted error. `FakeWorkspaceAdapter` also has settable connected displays and a per-display `setDesktopImage` failure. `InMemoryFileStore.onRead` hooks reads. `FakeClock(sleeping: .immediate)` completes every sleep at once, and `sleeps` records each requested duration. `StandardActionsHarness` runs the real controller, `StandardActionFactory` and `SessionStore` over these fakes for end-to-end tests, including a four-step profile (desktop icons, Dock, menu bar, hide apps) and a five-step profile with the wallpaper last, over `ActionPorts` and fixed fake `WallpaperLocations`.
- Deterministic: no real time, no real network, no dependence on the machine's state. Timers use `FakeClock` (`advance(by:)` wakes due sleepers). Controller suites carry a one-minute `timeLimit` so a hang fails instead of stalling.
- Never delete or weaken a test to make it pass. A failing test is fixed in the code or, if the requirement changed, rewritten with the doc change in the same PR.

## Mandatory scenarios for the session controller

1. Activate success: all actions captured, `session.json` written before the first apply, applied in order.
2. Apply failure at step N: steps before N restored in reverse order, session file removed, state idle, error surfaced.
3. Deactivate success: restore in reverse order, session file removed.
4. Restore failure on one action: others still restore, failed record kept, state `degraded`, retry succeeds later.
5. Conditional restore: value changed by the user meanwhile is not overwritten; reported as skipped.
6. Crash recovery: pre-existing `session.json` at launch triggers restore before any activation; corrupted file handled without crash; unknown `schemaVersion` handled without overwriting.
7. Reentrancy: trigger during applying or restoring is ignored.
8. Auto-exit timer fires with `FakeClock`; manual deactivate cancels it.
9. Empty profile (no steps), single step, all steps, duplicate steps.
10. Persistence atomicity: write failure leaves the previous file intact.
11. Activate before `recoverIfNeeded()` has finished throws `recoveryNotRun`.
12. Interrupted apply at recovery: a record with nil `appliedData` is restored unconditionally.
13. Stale timer: an auto-exit timer that fires while the user's deactivate is restoring does nothing.

After an interrupted restore, a later `skippedBecauseChangedByUser` can also mean the value was already restored; tests and the UI must not read it as proof that the user changed something.

## Per-action unit scenarios

For each action: capture reads current state; apply sets expected state; restore returns to captured; restore skips when changed; state already equal to target (for example Dock already auto-hidden: snapshot says so, restore leaves it hidden); the system call fails; timeout.

Specific edge cases to cover: Dock already auto-hidden; desktop icons already hidden; wallpaper file deleted between capture and restore; display disconnected between capture and restore; app in hide list not running; app quit during the session; user manually unhid an app during the session; Finder not running; the key absent at capture for desktop icons, Dock and menu bar (restore deletes, never writes a default); menu bar keys written explicitly by System Settings; Automation for System Events denied (-1743) or the prompt left unanswered (-1712 after 120 s); original wallpaper is a color or a dynamic wallpaper (restored from the store, not from `desktopImageURL`); a Space created during the session; Focus Shortcut missing (exit 1) or its state prompt unanswered (timeout).

## Platform adapter tests

The adapters' unit tests run on the developer's real Mac and in CI, so they follow strict safety rules (ADR-040).

They never do any of the following:
- write a real preferences domain (`com.apple.finder`, `com.apple.dock`, `com.apple.controlcenter`, `NSGlobalDomain`);
- run `killall`;
- post the menu bar notification;
- hide or unhide an application;
- call `setDesktopImageURL`;
- send an Apple event to another application;
- write the real wallpaper store.

Allowed real I/O is limited to the following:
- **Preferences:** a throwaway domain `dev.imyaxx.presenter.tests.<UUID>`, one per run of the defaults suite, with a fresh key per test (`ThrowawayPreferencesDomain`). A suite trait (`ThrowawayDomainCleanup`) removes its keys and its plist file after the suite. cfprefsd rewrites an emptied domain's file once, about 10 s after the last removal (machine-observed), so the cleanup waits up to 15 s for that rewrite and removes the file again.
- **Processes:** harmless commands only, such as `/usr/bin/true`, `/usr/bin/false`, `/bin/test`, `/bin/sleep`, a `/bin/sh` loop that ignores SIGTERM, `/usr/bin/pgrep`, and `/usr/bin/defaults write` on the throwaway domain.
- **AppleScript:** scripts that need no permission, such as `return 1 + 1`, `error number <n>` and `delay`.
- **Notifications:** a private distributed notification name of the test's own.
- **Files:** temporary files and directories.
- **Reading the live system:** running applications and screens. The real wallpaper store is read only by hand, to design the inspector; tests use sanitized fixtures under `App/Tests/Fixtures/WallpaperStore`, and a test checks that they contain no `/Users/` path, no user name and no UUID other than a placeholder.

The real effects (Finder, Dock, menu bar, hiding, the wallpaper) are verified by the check tool of the next branch under a backup and diff protocol, not by unit tests.

## Coverage targets

ModeKit at least 90% line coverage with meaningful assertions (coverage is a smell detector, not a goal). App view models at least 80%. Platform adapters are covered by manual QA and spikes, plus unit tests for their pure parsing and mapping logic.

New app code is measured with `xcodebuild test -enableCodeCoverage YES -resultBundlePath <path>` and `xcrun xccov view --report --json <path>`, at least 80%. Lines that change the real system are uncovered by design, and each branch lists them in its report. One example is the `setDesktopImageURL` call in `AppKitWorkspaceAdapter`. Defensive failure paths of system frameworks, such as a bitmap context or `CFPreferencesSynchronize` failing, are also uncovered.

## Manual QA checklists

Executed on a real Mac (record macOS version, date, result in the PR). Never reuse a previous run's result.

### Core session
- [ ] Activate with a profile containing all steps; every effect is visible.
- [ ] Deactivate; every effect is reverted; compare against a screenshot taken before.
- [ ] Activate, force-quit the app (`Force Quit` or `kill`), relaunch; state restores automatically.
- [ ] Activate, reboot, log in; state restores on launch (launch at login enabled).
- [ ] Activate, change Dock autohide manually, deactivate; manual change is preserved.
- [ ] Trigger twice rapidly; no double application, no stuck state.
- [ ] Auto-exit timer expires and restores.

### Per action
- [ ] Desktop icons: hidden and restored; Finder windows survive the restart; works with icons already hidden.
- [ ] Dock: hidden and restored; works when already auto-hidden; position unchanged.
- [ ] Menu bar: hidden and restored, on the desktop and in a full-screen app; System Settings shows the original value afterwards.
- [ ] Apps: only listed apps hide; the frontmost app is never hidden; only apps this app hid are unhidden; a closed app is not relaunched.
- [ ] Wallpaper: solid color and custom image on the current Space of every selected display; other Spaces unchanged; color, still-image and dynamic originals restored, including different originals per display; unplug and replug a display.

### Surfaces
- [ ] Appearance System / Light / Dark in every window and the HUD; live switch of the system appearance in System mode.
- [ ] English and Russian; no truncation.
- [ ] Keyboard-only navigation of the popover and settings; VoiceOver reads all controls.
- [ ] Permissions: first-run prompt flow; denial handled with a clear message and a path to System Settings.

### Release
- [ ] Fresh user account, fresh install from the release artifact: onboarding, first profile, activate, deactivate.
- [ ] Uninstall leaves no running process; no system setting left changed.

## CI

`ci.yml` on the pinned image `macos-26` (not `macos-latest`, so the toolchain changes only through a commit): checkout, install tools, `make verify`. PRs cannot merge on red. CI does not run manual system QA; the PR description records it.
