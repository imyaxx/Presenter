# Status

Last updated: 2026-10-17

## Current milestone

Bootstrap: done on branch `chore/bootstrap-repository`, pull request open, not merged. `main` holds the documentation commit only.

M0: platform spikes. Not started.

## Next step

1. User: review and squash-merge the bootstrap pull request; configure branch protection and merge options per `docs/05-git-workflow.md` (required check: `make verify`).
2. User: run the manual QA steps listed in the bootstrap pull request that need a person at the screen (popover content in English and Russian, Quit button).
3. M0 spikes on the user's Mac. See `docs/07-macos-integration.md`.

## Open decisions

| Decision | State |
|---|---|
| Product name and bundle identifier prefix | Open. Codename `Presenter` is used until decided. |
| Code signing and notarization | Open. Depends on audience. Build must work unsigned. |
| Focus / Do Not Disturb mechanism | Open. Decided after the M0 spike. |
| `swift-tools-version: 6.0` for ModeKit (ADR-024) | Decided by the assistant; user to confirm or reverse. |
| Product copy tone for the onboarding | Open. Decided in M4. |

## Known constraints

- Remote: `git@github.com:imyaxx/Presenter.git` (private, empty at 2026-10-17, no branch protection yet). Bootstrap prompt: `docs/prompts/00-bootstrap.md`.
- The user develops through Claude Code on a Mac. Tool versions verified on 2026-10-17 are in `docs/11-development-setup.md` (Xcode 27.1 locally; CI image `macos-26` with Xcode 26.6).
- Menu bar auto-hide and Dock auto-hide are global macOS settings. Per-display menu bar behavior is `UNVERIFIED` and assumed impossible. Wallpaper is per display.
- App cannot be sandboxed (modifies Finder and Dock settings, runs `defaults`, AppleScript). Not eligible for the Mac App Store.

## Session log

| Date | Milestone | What changed | Next |
|---|---|---|---|
| 2026-10-17 | Pre-M0 | Documentation and `CLAUDE.md` created | Bootstrap task |
| 2026-10-17 | Bootstrap | Repository initialized and pushed (`main`: docs only). Branch `chore/bootstrap-repository`: tooling configs, ModeKit skeleton, menu-bar app skeleton (EN/RU), Makefile, CI, setup guide | Merge bootstrap PR, then M0 |
