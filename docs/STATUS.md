# Status

Last updated: 2026-10-19

## Current milestone

Bootstrap: merged to `main` (`1c7f6e1`, 2026-10-17).

M2: app shell in progress.

- First branch `feat/platform-adapters` done, pull request open, not merged. It adds:
  - the real adapter for every ModeKit port (ADR-040): `CFPreferencesDefaultsStore`, `FoundationProcessRunner`, `NSAppleScriptRunner` on a dedicated thread, `AppKitWorkspaceAdapter` with `DisplayIdentifierMapping`, `DistributedNotificationCenterNotifier`, `CoreGraphicsSolidColorImageRenderer`, `PropertyListWallpaperStoreInspector` (ADR-041, sanitized fixtures), `OSSessionLogger` and `SystemLocations`;
  - the composition root `PlatformComposition`;
  - the Automation entitlement and the usage description in English and Russian (`InfoPlist.xcstrings`), verified on the built app.
- Tests: 67 app tests and 223 ModeKit tests. Line coverage of the new app code is 97.0% (`xcodebuild -enableCodeCoverage`, `xccov`). No test changed a real setting; the Finder, Dock and menu bar keys read the same before and after the test runs. The wallpaper store's modification time changed once during a test run, at the `LastUse` timestamps (docs/07); no code writes the store.
- Real effects are not verified yet: that is the next branch.

M1: ModeKit core complete, merged to `main` (`25ba26e`, 2026-10-18). All five actions are implemented against ports and tested with stateful fakes only; nothing has run through ModeKit on a real system.

- Fifth and last branch `feat/modekit-action-wallpaper` merged to `main` (`25ba26e`, 2026-10-18). It adds `WallpaperAction` with `WallpaperRestorer` (ADR-038): store bytes through `FileStore`, a fail-closed apply that fingerprints the store first, polling the store after setting the image, whole-file restore with `killall WallpaperAgent`. The store format stays behind the new `WallpaperStoreInspector` port (ADR-039). Also new: `SolidColorImageRenderer`, `WallpaperLocations`, the display members of `WorkspaceAdapter`, and `ActionPorts`; `StandardActionFactory.init(ports:wallpaperLocations:)` replaces the previous init and the factory supports all five steps. End-to-end tests run a five-step profile through the real controller, including rollback when the store never changes and crash recovery of the store bytes. 222 ModeKit tests; 100% line coverage of the code added in this branch, 98.1% of all ModeKit sources. No change to the controller, the stores or the file formats.
- Fourth branch `feat/modekit-actions-apps-menubar` merged to `main` (`47c492d`, 2026-10-18). It adds the `WorkspaceAdapter` and `DistributedNotifier` ports, `HideAppsAction` with `HideAppsRestorer` (ADR-036) and `MenuBarAction` (ADR-037), and extends `StandardActionFactory`. End-to-end tests run a four-step profile (desktop icons, Dock, menu bar, hide apps) through the real controller, including crash recovery and a refused unhide that degrades and is retried. 187 ModeKit tests; 100% line coverage of the code added in this branch, 97.9% of all ModeKit sources. No change to the controller, the stores or the file formats. The last M1 branch was split: the wallpaper action gets its own branch, `feat/modekit-action-wallpaper` (prompt 05).
- Third branch `feat/modekit-actions-desktop-icons-dock` merged to `main` (`5dc3721`, 2026-10-18). It adds the `DefaultsStore`, `ProcessRunner` and `AppleScriptRunner` ports (ADR-034), `DesktopIconsAction` and `DockAction` with skip-when-equal and the `killall` exit-1 rule (ADR-035), and `StandardActionFactory`. End-to-end tests run the real controller over stateful fakes. 150 ModeKit tests; 100% line coverage of the code added in this branch, 97.6% of all ModeKit sources. No change to the controller, the stores or the file formats.
- Second branch `feat/modekit-session-controller` merged to `main` (`7bb4531`, 2026-10-18). It adds the split action contract (`ActionRestorer`, `ModeAction`, `ActionFactory`, ADR-032), the `SessionClock` and `SessionLogger` ports, and the `SessionController` actor: activate with per-action persistence, rollback, deactivate, the auto-exit timer, crash recovery, retry and discard of an unreadable file. It also adds durable writes with `F_FULLFSYNC` (ADR-033) and settles the apply order (ADR-031). 112 ModeKit tests; 95.3% line coverage of the code added in this branch, 97.1% of all ModeKit sources.
- First branch `feat/modekit-models-and-persistence` merged to `main` (`18a762d`, 2026-10-18): domain models and `ProfileValidation`, the `FileStore` port and the atomic `FileManagerFileStore` (ADR-029), `ProfileStore` and `SessionStore` with schema version and file policy (ADR-030), `SessionRecord` and `ActionRecord`. Formats: `docs/12-data-formats.md`.

M0: platform spikes merged to `main` (`4e935bc`, 2026-10-17). All six spikes have verdicts in `docs/07-macos-integration.md` (spike log). Tested on macOS 27.0 (26A428), Mac17,9, one display, Xcode 27.1.

| Spike | Verdict | Mechanism for M1 |
|---|---|---|
| S5 Desktop icons | pass | `CreateDesktop` + `killall Finder`; delete the key if absent (ADR-028) |
| S4 Dock | pass | System Events AppleScript; entitlement + usage description required; `defaults delete` for absent (ADR-025) |
| S1 Menu bar | pass | three keys + `AppleInterfaceMenuBarHidingChangedNotification`; no permission (ADR-026) |
| S2 Wallpaper | pass, design change | apply via NSWorkspace on the current Space only; capture and restore the store `Index.plist` + `killall WallpaperAgent` (ADR-027) |
| S6 Hotkey | pass | `KeyboardShortcuts` 3.1.0, no Accessibility or Input Monitoring prompt |
| S3 Focus | pass; distribution blocked | user-built Shortcuts via `shortcuts run`; prebuilt file needs iCloud (ADR-013 proposed) |

Not verified: macOS 14 and 15, a second display, wallpaper on all Spaces at once, `CGDisplayCreateUUIDFromDisplayID` stability across reboot, the hide-apps and launch-at-login mechanisms (no M0 spike), importing a signed `.shortcut`. Hide apps and menu bar now run in ModeKit against fakes only: the effect of `NSRunningApplication.hide()` and `unhide()`, several instances of one bundle identifier, full-screen applications, and the effect of the menu bar notification posted from the real app are not verified on a real system (docs/07). The wallpaper action runs against fakes only: the store format as the inspector sees it, the latency between setting the image and the store change (the 100 ms by 50 polling constants are guesses), restoring through an atomic replace of `Index.plist`, `killall WallpaperAgent` exit 1, several Spaces and a full-screen Space are not verified.

## Next step

1. User: review and squash-merge the `feat/platform-adapters` pull request. Confirm or reverse ADR-040 and ADR-041 (still pending: ADR-013, ADR-023, ADR-025 to ADR-039).
2. M2, next branch `feat/adapter-check-tool` (`docs/08-roadmap.md`): a checked-in developer tool that runs the real adapters through the real controller under a backup and diff protocol.
3. **Before the check tool changes anything, the user takes a backup**, and the tool's protocol restores from it and diffs against it. The backup covers:
   - the preferences domains `com.apple.finder`, `com.apple.dock`, `com.apple.controlcenter` and `NSGlobalDomain`, exported with `defaults export`;
   - a copy of `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`;
   - the list of running regular applications with their hidden state;
   - a screenshot of the desktop.
4. What the check tool must verify (open `UNVERIFIED` items):
   - **Preferences.** `CFPreferences` read and write for `com.apple.finder` and `com.apple.dock` from the app, else switch to the `defaults` tool through `ProcessRunner`.
   - **AppleScript.**
     - `NSAppleScript` on the background thread sending Apple events to System Events.
     - The real Automation prompt and its denial (-1743) and timeout (-1712) through the runner.
   - **Hide apps.**
     - The effect of `NSRunningApplication.hide()` and `unhide()` and their return values.
     - Several instances of one bundle identifier.
     - Full-screen applications.
   - **Menu bar.** The notification posted from the real app, and reading the three keys from the real app.
   - **Wallpaper.**
     - `setDesktopImageURL` through the adapter.
     - The store structure after a real apply of a solid color and of an image, and the inspector against it (ADR-041).
     - The latency between `setDesktopImageURL` and the store change, to recalibrate the 100 ms by 50 polling.
     - An atomic replace of `Index.plist` followed by `killall WallpaperAgent`.
     - Whether restarting the agent discards a change it has not yet persisted.
   - **`killall`.** Exit codes for Finder and WallpaperAgent (exit 1 on a running system).
   - **Displays and Spaces.** A second display, several Spaces and a full-screen Space.
5. Added by this branch:
   - The AppleScript watchdog against a real blocked script.
   - The `Info.plist` usage description shown in the real Automation prompt, in English and Russian.
6. Leftovers on the user's Mac, kept for the user to remove. From this branch: about 40 empty `~/Library/Preferences/dev.imyaxx.presenter.tests.*.plist` files left by early runs of the defaults tests, before the cleanup waited for cfprefsd; the current tests leave none. From the M0 spikes: `$HOME/presenter-spikes/` (backup and throwaway code); defaults domains `dev.imyaxx.presenter.spike.hotkey-adhoc` and `...hotkey-runtime`; the three "Presenter Focus" Shortcuts and their "Always Allow" focus-output grant; Media & Apple Music access for the Claude app, granted during S1 key discovery.

## Open decisions

| Decision | State |
|---|---|
| Product name and bundle identifier prefix | Open. Codename `Presenter` is used until decided. |
| Code signing and notarization | Open. Depends on audience. Build must work unsigned. |
| Focus / Do Not Disturb mechanism | ADR-013 proposed after S3: optional v1.0 action with a manual Shortcut setup guide; user to confirm. |
| Dock, menu bar, wallpaper, desktop icons mechanisms (ADR-025 to ADR-028), menu bar kept in v1 (ADR-023) | Proposed by the assistant from M0 evidence; user to confirm. |
| `swift-tools-version: 6.0` for ModeKit (ADR-024) | Decided by the assistant; user to confirm or reverse. |
| Real `FileStore` in ModeKit (ADR-029); on-disk format and file policy (ADR-030) | Proposed by the assistant in M1; user to confirm. |
| Apply order (ADR-031), action contract and ports (ADR-032), durable writes (ADR-033) | Proposed by the assistant in M1; user to confirm. |
| Controller watchdog for a hung action | Not built (ADR-032); revisit if an adapter cannot bound its own wait. |
| System ports and literal scripts (ADR-034), skip-when-equal and `killall` exit 1 (ADR-035) | Proposed by the assistant in M1; the `killall` rule was confirmed by the user on 2026-10-18; the rest awaits confirmation. |
| Hide apps ports and semantics (ADR-036), menu bar action (ADR-037) | Proposed by the assistant in M1; user to confirm. |
| Reporting applications that refused to hide or quit | Not built: no channel to the user exists yet. |
| Wallpaper action (ADR-038), store format behind `WallpaperStoreInspector` (ADR-039), `ActionPorts` factory init | Proposed by the assistant in M1; user to confirm. |
| Reporting skipped (disconnected) displays | Not built: no channel to the user exists yet. |
| Platform adapter conventions (ADR-040), wallpaper store fingerprint (ADR-041) | Proposed by the assistant in M2; user to confirm. |
| Dock `autohide` stored as a non-boolean (for example `integer 1`) | Treated as "off" for the script (decision in prompt 04), then written back with its type. Not observed on a real system. |
| Product copy tone for the onboarding | Open. Decided in M4. |

## Known constraints

- Remote: `git@github.com:imyaxx/Presenter.git` (private, empty at 2026-10-17, no branch protection yet). Bootstrap prompt: `docs/prompts/00-bootstrap.md`.
- The user develops through Claude Code on a Mac. Tool versions verified on 2026-10-17 are in `docs/11-development-setup.md` (Xcode 27.1 locally; CI image `macos-26` with Xcode 26.6).
- Menu bar auto-hide and Dock auto-hide are global macOS settings. Per-display menu bar behavior is `UNVERIFIED` and assumed impossible. Wallpaper is per display and per Space; the app changes only the current Space (S2).
- App cannot be sandboxed (modifies Finder and Dock settings, runs `defaults`, AppleScript). Not eligible for the Mac App Store.

## Session log

| Date | Milestone | What changed | Next |
|---|---|---|---|
| 2026-10-17 | Pre-M0 | Documentation and `CLAUDE.md` created | Bootstrap task |
| 2026-10-17 | Bootstrap | Repository initialized and pushed (`main`: docs only). Branch `chore/bootstrap-repository`: tooling configs, ModeKit skeleton, menu-bar app skeleton (EN/RU), Makefile, CI, setup guide | Merge bootstrap PR, then M0 |
| 2026-10-17 | M0 | Spikes S1 to S6 run on the user's Mac with backup, per-spike diffs and a final diff; results in docs/07, ADR-023 closed, ADR-013 proposed, ADR-025 to ADR-028 added, architecture, brief and test scenarios adjusted | Confirm ADRs, merge, M1 |
| 2026-10-18 | M1 | Branch `feat/modekit-models-and-persistence`: models, validation, `FileStore`, `FileManagerFileStore`, `ProfileStore`, `SessionStore`, ADR-029, ADR-030, `docs/12-data-formats.md` | Merge, then `feat/modekit-session-controller` |
| 2026-10-18 | M1 | Branch `feat/modekit-actions-desktop-icons-dock`: `DefaultsStore`, `ProcessRunner`, `AppleScriptRunner` ports, `DesktopIconsAction`, `DockAction`, `StandardActionFactory`, end-to-end tests, ADR-034, ADR-035 | Merge, then `feat/modekit-actions-apps-wallpaper-menubar` |
| 2026-10-18 | M1 | Branch `feat/modekit-session-controller`: action contract, `SessionClock`, `SessionLogger`, `SessionController` (activate, rollback, deactivate, timer, recovery, retry, discard), `F_FULLFSYNC` writes, ADR-031 to ADR-033 | Merge, then `feat/modekit-actions-desktop-icons-dock` |
| 2026-10-18 | M1 | Branch `feat/modekit-actions-apps-menubar`: `WorkspaceAdapter`, `DistributedNotifier` ports, `HideAppsAction`, `HideAppsRestorer`, `MenuBarAction`, factory, four-step end-to-end tests, ADR-036, ADR-037; wallpaper split into its own branch | Merge, then `feat/modekit-action-wallpaper` |
| 2026-10-18 | M1 | Branch `feat/modekit-action-wallpaper`: `WallpaperAction`, `WallpaperRestorer`, `WallpaperStoreInspector`, `SolidColorImageRenderer`, `WallpaperLocations`, `ActionPorts`, display members of `WorkspaceAdapter`, factory for all five steps, five-step end-to-end tests, ADR-038, ADR-039; M1 complete in code | Merge, then M2 `feat/platform-adapters` |
| 2026-10-19 | M2 | Branch `feat/platform-adapters`: real adapters for every port, `PlatformComposition`, Automation entitlement and localized usage description, sanitized wallpaper store fixtures, ADR-040, ADR-041; no real setting changed by any test | Merge, then `feat/adapter-check-tool` |
