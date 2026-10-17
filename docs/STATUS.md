# Status

Last updated: 2026-10-17

## Current milestone

M0: platform spikes. Not started. Repository contains documentation only.

## Next step

1. Bootstrap task: `git init`, `main` branch, `.gitignore`, `.editorconfig`, `project.yml`, `Packages/ModeKit` skeleton, `Makefile`, lint and format configs, CI. See `docs/08-roadmap.md` section "Bootstrap".
2. M0 spikes on the user's Mac. See `docs/07-macos-integration.md`.

## Open decisions

| Decision | State |
|---|---|
| Product name and bundle identifier prefix | Open. Codename `Presenter` is used until decided. |
| Code signing and notarization | Open. Depends on audience. Build must work unsigned. |
| Focus / Do Not Disturb mechanism | Open. Decided after the M0 spike. |
| Product copy tone for the onboarding | Open. Decided in M4. |

## Known constraints

- Remote: `git@github.com:imyaxx/Presenter.git` (private, empty at 2026-10-17, no branch protection yet). Bootstrap prompt: `docs/prompts/00-bootstrap.md`.
- The user develops through Claude Code on a Mac. Xcode must be installed (not installed at 2026-10-17; user will install it).
- Menu bar auto-hide and Dock auto-hide are global macOS settings. Per-display menu bar behavior is `UNVERIFIED` and assumed impossible. Wallpaper is per display.
- App cannot be sandboxed (modifies Finder and Dock settings, runs `defaults`, AppleScript). Not eligible for the Mac App Store.

## Session log

| Date | Milestone | What changed | Next |
|---|---|---|---|
| 2026-10-17 | Pre-M0 | Documentation and `CLAUDE.md` created | Bootstrap task |
