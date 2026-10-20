# Roadmap

Each milestone ends with: `make verify` green, manual QA for touched areas recorded, docs updated, branch merged to `main` by squash PR. Milestones are split into several branches; one branch per feature.

## Bootstrap (before M0 and M1)

Branch: `chore/bootstrap-repository`.
Deliverables: `git init` with `main`; `.gitignore` (Xcode, SwiftPM, macOS, `*.xcodeproj`), `.editorconfig`, `LICENSE` (MIT), `project.yml`, `Packages/ModeKit` skeleton with one passing test, `App/` skeleton (`@main`, menu-bar extra with a placeholder-free minimal real view, `LSUIElement`), `Makefile` with the canonical targets, `.swiftlint.yml`, `.swift-format`, `.github/workflows/ci.yml`, `.github/pull_request_template.md`, and a dev setup section in `docs/` (tools installed via Homebrew: `xcodegen`, `swiftlint`, `swift-format`).
Acceptance: fresh clone, `make generate && make verify` passes; CI green on the PR.
Prerequisite on the user's Mac: Xcode (current stable), Homebrew, GitHub remote created, branch protection configured per `docs/05-git-workflow.md`.

## M0: platform spikes

Branch: `docs/m0-platform-spikes` (docs only, plus optional verified spike scripts).
Run spikes S1 to S6 from `docs/07-macos-integration.md` on the user's Mac. Record results in the spike log. Update ADRs: ADR-013 (Focus), menu bar action feasibility, Dock mechanism.
Acceptance: every spike has a verdict with evidence; open decisions closed or explicitly deferred; `docs/01-architecture.md` adjusted if a spike changes the design.
Status: **done on branch `docs/m0-platform-spikes`, 2026-10-17, macOS 27.0 only.** Verdicts: S1 pass, S2 pass with design change, S3 pass (prebuilt Shortcut distribution blocked), S4 pass, S5 pass, S6 pass. ADR-023 closed. ADR-013 and ADR-025 to ADR-028 await user confirmation. macOS 14 and 15 and multi-display are untested.

## M1: ModeKit core

Branches (sequential, each merged separately): `feat/modekit-models-and-persistence`, `feat/modekit-session-controller`, `feat/modekit-actions-desktop-icons-dock`, `feat/modekit-actions-apps-menubar`, `feat/modekit-action-wallpaper`. The last planned branch, `feat/modekit-actions-apps-wallpaper-menubar`, was split in two (prompt 05): the wallpaper action is the riskiest (undocumented store file, polling for the agent) and gets its own branch.
Status: **complete in code with `feat/modekit-action-wallpaper` (2026-10-18), pending its merge.** All five actions are implemented against ports and tested with fakes only. Nothing has run through ModeKit on a real system.
Deliverables: domain models; ports and fakes; `ProfileStore` and `SessionStore` with atomic writes and schema versions; `SessionController` actor with the state machine, rollback, conditional restore, crash recovery, timer; actions implemented against ports.
Acceptance: all mandatory scenarios in `docs/06-testing.md` pass; ModeKit coverage target met; zero imports other than Foundation.

## M2: app shell

Branches: `feat/platform-adapters`, `feat/adapter-check-tool`, `feat/menubar-shell`, `feat/hud`, `feat/hotkey`, `feat/design-system-foundation`, `feat/theme-controller`.
First branch `feat/platform-adapters` (merged 2026-10-19): the real adapter for every ModeKit port, the composition root, the Automation entitlement and the localized usage description. It is built and tested under safety rules: no test changes a real setting (ADR-040).
`feat/adapter-check-tool`: a checked-in developer tool that runs the real adapters through the real controller under a backup and diff protocol, and verifies the unverified items (list in `docs/STATUS.md`). The tool is a DEBUG-only mode of the app (ADR-042); its protocol is `docs/13-adapter-check.md`. Done, pending merge: the protocol ran on 2026-10-20 on macOS 27.0.1 (docs/07, C0 to C10) and fixed two adapter defects.
Deliverables: real platform adapters; menu-bar extra with the three icon states; popover with profile list and activate/deactivate; HUD; hotkey registration; launch at login; design tokens, theme controller (System/Light/Dark), L10n infrastructure with EN and RU; design pass confirming accent and icon set.
Acceptance: end-to-end activate and deactivate of a hand-written `profiles.json` profile using real system effects; core session and per-action manual QA checklists pass; crash and reboot recovery verified manually.

## M3: settings

Branches: `feat/settings-shell`, `feat/settings-profiles`, `feat/settings-general`, `feat/settings-appearance`, `feat/settings-permissions`.
Deliverables: Settings window; profile CRUD with editor for every step type, per-display wallpaper selection, solid color or image, exclusion list, auto-exit timer; General (hotkey, launch at login, language); Appearance (System/Light/Dark); Permissions status with deep links to System Settings.
Acceptance: a non-technical user can create and run a profile with no file editing; language and theme changes take effect as documented; settings QA passes.

## M4: onboarding

Branch: `feat/onboarding`.
Deliverables: first-run flow; permission request through a real action; optional Focus shortcut step if ADR-013 ships it; skip paths; reachable from Settings later.
Acceptance: fresh-account run-through documented with screenshots.

## M5: release

Branches: `ci/release-workflow`, `docs/readme-and-demo`, `chore/release-1.0.0`.
Deliverables: release workflow producing a zip (and DMG if chosen) attached to a GitHub Release; signing and notarization steps behind secrets when credentials exist, ad-hoc signed build otherwise with Gatekeeper instructions; Homebrew cask in a tap; README with a 5-second before/after GIF, install, permissions, privacy statement (no network), contributing, license; issue templates; CHANGELOG from Conventional Commits.
Acceptance: release checklist in `docs/06-testing.md` passes on a clean account.

## After v1.0 (not committed)

Calendar and app-launch triggers; CLI; Sparkle updates if audience justifies signing; additional actions (volume mute, display brightness, Do Not Disturb if viable).
