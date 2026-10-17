You are a senior macOS and Swift engineer with more than 15 years of experience shipping production software. You write clean, stable, readable code with precise names and clear architecture. You do not write demo-quality or "vibe" code. You verify your work before declaring it done. You never state a platform fact you have not observed. You are working in an existing repository with strict rules.

## Context to read first (mandatory, in order)
1. CLAUDE.md
2. docs/STATUS.md
3. docs/README.md, then: docs/07-macos-integration.md (the spike definitions and current hypotheses), docs/08-roadmap.md (section "M0"), docs/09-decisions.md (ADR-006, 010, 011, 013, 022, 023), docs/01-architecture.md (what depends on the outcome), docs/05-git-workflow.md, docs/10-claude-code-protocol.md
Do not start until you have read them. If anything here contradicts the docs, stop and report it.

## Objective
Replace every `UNVERIFIED` platform hypothesis behind the six actions with an observed fact, or an explicit verdict, so that M1 and M2 are built on evidence. The output is documentation: spike log entries with reproducible evidence, updated mechanism sections, closed or explicitly deferred ADRs, and a corrected architecture where a spike changes the design. No product code is written.

## Environment and safety
- The user is at this Mac and will answer questions in this session. The spikes change real system settings: Finder, Dock, menu bar, wallpaper. Treat the machine as the user's daily machine.
- Spike work lives outside the repository in `$HOME/presenter-spikes/` (scripts, throwaway Swift packages, throwaway app bundles, backups). Nothing from there is committed unless it meets the rule in docs/07 ("Spikes"): documents a verified fact, is lint-clean under `make verify`.
- Before the first change, create `$HOME/presenter-spikes/backup-<UTC timestamp>/` containing: `defaults export` of `com.apple.finder`, `com.apple.dock`, `NSGlobalDomain`, `com.apple.controlcenter`, `com.apple.WindowManager`; a copy of `~/Library/Application Support/com.apple.wallpaper/` if present; for each `NSScreen` the `desktopImageURL` and `desktopImageOptions`; the list of running regular apps; `sw_vers`, `system_profiler SPDisplaysDataType` summary, number of displays. Print the backup path to the user.
- Every spike follows the same cycle and no step is skipped: record baseline, announce the change to the user in one line (and warn before any Finder or Dock restart, which flickers), apply, observe, restore, then diff against the baseline. If the diff is not empty, stop, restore from the backup, report exactly what differs, and do not continue to the next spike.
- Run spikes one at a time, in the order S5, S4, S1, S2, S6, S3 (lowest to highest risk and effort). Do not parallelize anything that touches system state.
- Commands that discover a key by diffing: the user changes a setting by hand in System Settings, you diff `defaults export` before and after. This is the reference method for finding the real key and value domain; do not rely on memory or web pages for key names.
- You cannot take screenshots. Whenever a result is visual (menu bar visible, wallpaper on a given Space, Dock hidden, Finder windows), stop, ask the user one exact question (what to look at, which answers are possible), wait, and record the user's answer as human-verified. Machine-checkable facts (`defaults read`, return codes, timings) are recorded as machine-verified. Label every spike log line with which kind it is.

## Scope (do exactly this)
1. S5 Desktop icons. Mechanism `defaults write com.apple.finder CreateDesktop` plus Finder restart. Verify: behavior when the key is absent (restore must delete it, not write `true`); `defaults export com.apple.finder -` identical to the baseline after restore; effect on open Finder windows (user opens two Finder windows in different folders before; report what survives the restart); time from command to icons gone and back (measured); whether `killall Finder` is enough or a different restart is needed.
2. S4 Dock auto-hide. Compare A (System Events AppleScript `autohide of dock preferences`) and B (`defaults write com.apple.dock autohide` plus `killall Dock`). Verify for each: immediacy, flicker, effect on `defaults read com.apple.dock autohide` (does A write the preference), restore correctness including the key-absent case. For A, test from a real throwaway signed app bundle with its own bundle id (osascript from Terminal would prompt for Terminal, which proves nothing): build a minimal Swift app in `$HOME/presenter-spikes/`, sign it manually with `codesign --options runtime` (ad-hoc signing from Xcode does not apply the hardened runtime, see docs/07 "Verified build facts"). Record: the exact text of the Automation permission prompt, whether `NSAppleEventsUsageDescription` is required, whether `com.apple.security.automation.apple-events` is required under hardened runtime (test with and without), what the failure looks like without it, and how to reset for retest (`tccutil reset AppleEvents <bundle id>`, only for the spike bundle id).
3. S1 Menu bar hide. Find the real mechanism. Use the diff method: the user toggles "Automatically hide and show the menu bar" in System Settings, Control Center, through every available value on this macOS version; capture which key in which domain changes and to what values. Then test whether writing that key from the command line and from the throwaway app applies live, or needs `killall SystemUIServer`, `killall ControlCenter`, or logout. Verify restore including key-absent. Verify what the user observes (human-verified) in desktop mode and with a full-screen app. Verdict: a live mechanism exists (record exact key, domain, value domain, required refresh) or the action is dropped from v1 (ADR-023).
4. S2 Wallpaper. Ask the user to create a setup with at least two Spaces (and, if available, a second display; if not available, record that multi-display is untested). Verify with a small Swift script using `NSWorkspace`: what `desktopImageURL(for:)` and `desktopImageOptions(for:)` return for a static wallpaper, a dynamic/system wallpaper, and a color; whether `setDesktopImageURL` changes all Spaces or only the current one (user visits each Space and reports); whether restoring the captured URL and options reproduces the original, including for a dynamic wallpaper; what `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` contains and whether it is a better capture source; the stable display key (`CGDisplayCreateUUIDFromDisplayID` vs alternatives, stability across reboot is untestable now and must be recorded as untested). Generate a solid-color PNG and verify it applies. Restore correctness is judged by the user visually on every Space plus identical file listings in the backup directory.
5. S6 Hotkey. In a throwaway Swift package in `$HOME/presenter-spikes/` depend on `KeyboardShortcuts` (sindresorhus/KeyboardShortcuts, pin the latest release tag, record it). Build an app bundle, sign ad hoc, and separately with `codesign --options runtime`. Verify: registration works; the user presses the combination and the handler fires (human-verified); no Accessibility or Input Monitoring prompt appears (human-verified, plus `tccutil`/System Settings state before and after); behavior while another app is frontmost and while a full-screen app is frontmost. Only the macOS version on this Mac can be tested; record 14 and 15 as untested unless the user has access to them.
6. S3 Focus. Inspect `shortcuts` (subcommands, `list`, `run`, `sign`), and what a Shortcut can do with Focus on this version. Determine: whether a Shortcut file can be shipped and imported with minimal user steps (count the clicks and prompts when importing a signed `.shortcut`), whether it can set Focus on and off, whether the previous Focus state can be read by any means (Shortcut action, `defaults`, `plutil` of the Focus assertions store, notification center state), latency of `shortcuts run` end to end (measured, 5 runs), and failure behavior when the Shortcut is missing. If importing needs a manual Shortcuts-app build by the user, write the exact steps the user would follow. Verdict: ship in v1.0, defer to v1.1, or drop (ADR-013), with the reason in one paragraph.
7. Write results into `docs/07-macos-integration.md`: one spike log entry per spike (`### S<ID> <date> macOS <version>`) with command, observation, evidence kind (machine/human), verdict; update the action sections so each hypothesis is either marked verified with a pointer to its log entry or still `UNVERIFIED` with the reason it could not be tested; move durable facts into "Verified build facts" only if they are about the build, not about an action.
8. Update `docs/09-decisions.md`: close or revise ADR-013 and ADR-023; add new ADRs (next numbers after the highest existing) for the Dock mechanism, and for any other decision a spike forces (for example the desktop-icons restart strategy, the wallpaper capture source, entitlement requirements). Each new ADR states context, decision, consequence, and who decided (the assistant proposes, the user confirms).
9. If a spike changes the design (for example the wallpaper snapshot shape, a port's contract, or an action being dropped), adjust `docs/01-architecture.md`, `docs/00-product-brief.md` scope lines and `docs/06-testing.md` scenarios minimally and list each change in the report.
10. Update `docs/08-roadmap.md` (mark M0 done only if every spike has a verdict) and `docs/STATUS.md` (milestone, what is verified, what is not, next step M1, open decisions).

## Out of scope (do not do)
- Any product code under `App/` or `Packages/`. No adapters, no models.
- Choosing the product name, signing identity, or notarization setup (ADR-022 stays open).
- Fixing anything you notice outside the spikes. List it under "Observed but not done".
- Leaving any setting changed. Any state not restored is a failure to report, not to hide.

## Requirements
- Evidence standard: every claim in the docs has a command or a user observation behind it in the spike log. No claim from memory or from a web page unless labelled as such and not used to close an item.
- Record the exact macOS version and build (`sw_vers`), hardware model, display count, and Xcode version in each log entry.
- Timings are measured, with the number of runs stated; do not write "fast" or "instant".
- Language of docs: English, plain, no filler. Tables only where they compare.
- Code in `$HOME/presenter-spikes/` may be rough, but any script you commit must follow docs/03-code-standards.md and pass `make lint`.
- A spike that cannot be completed (missing hardware, permission denied, tool absent) gets verdict `blocked` with the reason and what is needed, never a guess.

## Acceptance criteria
- [ ] Backup directory exists and its path was printed.
- [ ] Each of S1 to S6 has a spike log entry with evidence kind and verdict.
- [ ] After each spike, the diff against its baseline is empty (or the discrepancy is reported and the run stopped).
- [ ] At the end, `defaults export` of the five domains and the wallpaper state equal the backup, shown by diff output quoted in the report.
- [ ] No remaining `UNVERIFIED` tag in docs/07 without a stated reason.
- [ ] ADR-013 and ADR-023 are closed or explicitly deferred with a date and reason; new ADRs added where decisions were forced.
- [ ] `docs/STATUS.md` lets a fresh session start M1 without history.
- [ ] `make verify` passes. `git status` shows no files outside `docs/` and, if any, `Scripts/spikes/`.

## Test plan
- Automated: none for docs. If a spike script is committed, it must be covered by `make lint` and documented in docs/07.
- Commands: `make verify`.
- Manual QA: the human-verified questions in the spikes above, asked one at a time in this session; a final check that the user sees their original Dock, menu bar, desktop icons, and wallpaper on every Space.

## Git instructions
- Start from an up-to-date main: `git fetch origin --prune; git switch main; git pull --ff-only`.
- This prompt file is untracked in the working tree. Create branch `docs/m0-platform-spikes`, then make this file the first commit: `docs(prompts): add M0 platform spikes prompt`.
- Then commit atomically with Conventional Commits, for example: one `docs(spikes): record S5 ...` commit per spike (log entry plus the mechanism section it changes), one `docs(decisions): ...` commit for ADRs, one `docs(architecture): ...` commit if the design changed, one `docs(status): ...` commit last. Stage files explicitly (never `git add .` or `-A`). Read `git diff --cached` before each commit.
- Run `make verify` before every commit. Never use `--no-verify`.
- Push the branch and open a PR titled "docs: record M0 platform spike results". The PR body follows `.github/pull_request_template.md`, lists each spike verdict in one line, and links ADR changes.
- Do not merge.

## Docs to update in the same branch
docs/07-macos-integration.md, docs/09-decisions.md, docs/08-roadmap.md, docs/STATUS.md, and docs/01-architecture.md, docs/00-product-brief.md, docs/06-testing.md only if a spike changes them.

## Report format
Branch, Commits, Files changed, make verify result, Manual QA (including the final restore diff), Docs updated, Observed but not done, Unverified, Next step (see docs/10-claude-code-protocol.md). Add a table at the top of the report: spike, verdict, evidence kind, what it changes in the plan.
