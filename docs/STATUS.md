# Status

Last updated: 2026-10-18

## Current milestone

Bootstrap: merged to `main` (`1c7f6e1`, 2026-10-17).

M1: ModeKit core in progress. First branch `feat/modekit-models-and-persistence` done, pull request open, not merged: domain models and `ProfileValidation`, the `FileStore` port and the atomic `FileManagerFileStore` (ADR-029), `ProfileStore` and `SessionStore` with schema version and file policy (ADR-030), `SessionRecord` and `ActionRecord`. 63 ModeKit tests; 99.0% line coverage of ModeKit sources. Formats: `docs/12-data-formats.md`.

M0: platform spikes merged to `main` (`4e935bc`, 2026-10-17). All six spikes have verdicts in `docs/07-macos-integration.md` (spike log). Tested on macOS 27.0 (26A428), Mac17,9, one display, Xcode 27.1.

| Spike | Verdict | Mechanism for M1 |
|---|---|---|
| S5 Desktop icons | pass | `CreateDesktop` + `killall Finder`; delete the key if absent (ADR-028) |
| S4 Dock | pass | System Events AppleScript; entitlement + usage description required; `defaults delete` for absent (ADR-025) |
| S1 Menu bar | pass | three keys + `AppleInterfaceMenuBarHidingChangedNotification`; no permission (ADR-026) |
| S2 Wallpaper | pass, design change | apply via NSWorkspace on the current Space only; capture and restore the store `Index.plist` + `killall WallpaperAgent` (ADR-027) |
| S6 Hotkey | pass | `KeyboardShortcuts` 3.1.0, no Accessibility or Input Monitoring prompt |
| S3 Focus | pass; distribution blocked | user-built Shortcuts via `shortcuts run`; prebuilt file needs iCloud (ADR-013 proposed) |

Not verified: macOS 14 and 15, a second display, wallpaper on all Spaces at once, `CGDisplayCreateUUIDFromDisplayID` stability across reboot, the hide-apps and launch-at-login mechanisms (no M0 spike), importing a signed `.shortcut`.

## Next step

1. User: review and squash-merge the `feat/modekit-models-and-persistence` pull request; confirm or reverse ADR-029 and ADR-030 (and, still pending from M0, ADR-013, ADR-023, ADR-025 to ADR-028).
2. M1, next branch `feat/modekit-session-controller` (`docs/08-roadmap.md`): `SessionController` actor, state machine, rollback, conditional restore, crash recovery, timer, against the stores of this branch. It adds the `Clock` port. Schema version 1 may still change shape without a migration (pre-release rule, ADR-030).
3. Unresolved doc conflict to settle before the session controller: `docs/00-product-brief.md` says actions apply "in a fixed order", `docs/01-architecture.md` says "in profile order". The stored format keeps the profile's array order.
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
| Apply order: fixed (`docs/00`) or profile order (`docs/01`) | Open conflict between docs; the data layer stores profile order. |
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
