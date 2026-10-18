# Status

Last updated: 2026-10-18

## Current milestone

Bootstrap: merged to `main` (`1c7f6e1`, 2026-10-17).

M1: ModeKit core in progress.

- Fourth branch `feat/modekit-actions-apps-menubar` done, pull request open, not merged. It adds the `WorkspaceAdapter` and `DistributedNotifier` ports, `HideAppsAction` with `HideAppsRestorer` (ADR-036) and `MenuBarAction` (ADR-037), and extends `StandardActionFactory`. End-to-end tests run a four-step profile (desktop icons, Dock, menu bar, hide apps) through the real controller, including crash recovery and a refused unhide that degrades and is retried. 187 ModeKit tests; 100% line coverage of the code added in this branch, 97.9% of all ModeKit sources. No change to the controller, the stores or the file formats. The last M1 branch was split: the wallpaper action gets its own branch, `feat/modekit-action-wallpaper` (prompt 05).
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

Not verified: macOS 14 and 15, a second display, wallpaper on all Spaces at once, `CGDisplayCreateUUIDFromDisplayID` stability across reboot, the hide-apps and launch-at-login mechanisms (no M0 spike), importing a signed `.shortcut`. Hide apps and menu bar now run in ModeKit against fakes only: the effect of `NSRunningApplication.hide()` and `unhide()`, several instances of one bundle identifier, full-screen applications, and the effect of the menu bar notification posted from the real app are not verified on a real system (docs/07).

## Next step

1. User: review and squash-merge the `feat/modekit-actions-apps-menubar` pull request; confirm or reverse ADR-036 and ADR-037 (still pending: ADR-013, ADR-023, ADR-025 to ADR-035).
2. M1, next and last branch `feat/modekit-action-wallpaper` (`docs/08-roadmap.md`): the wallpaper action (ADR-027), the display and wallpaper members of `WorkspaceAdapter`, extend `StandardActionFactory`.
3. M2 requirement from the desktop icons and Dock branch, unchanged, for `feat/platform-adapters` (the first branch with a real `AppleScriptRunner`): add the `com.apple.security.automation.apple-events` entitlement and `NSAppleEventsUsageDescription` (ADR-025), localized. Proposed wording, English: "Presenter controls the Dock's auto-hide setting through System Events while a profile is active." Russian: "Presenter управляет автоматическим скрытием Дока через System Events, пока профиль активен." The same branch must verify in-app `CFPreferences` access to `com.apple.finder` and `com.apple.dock`, or use the `defaults` tool through `ProcessRunner` (docs/07), and must enforce the 10 s `killall` and 130 s AppleScript timeouts in the adapters.
4. Spike leftovers on the user's Mac, kept for the user to remove: `$HOME/presenter-spikes/` (backup and throwaway code); defaults domains `dev.imyaxx.presenter.spike.hotkey-adhoc` and `...hotkey-runtime`; the three "Presenter Focus" Shortcuts and their "Always Allow" focus-output grant; Media & Apple Music access for the Claude app, granted during S1 key discovery.

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
