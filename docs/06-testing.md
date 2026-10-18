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

## Coverage targets

ModeKit at least 90% line coverage with meaningful assertions (coverage is a smell detector, not a goal). App view models at least 80%. Platform adapters are covered by manual QA and spikes, plus unit tests for their pure parsing and mapping logic.

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
