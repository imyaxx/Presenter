# macOS integration

How each system change is performed, what is verified, and what is not. **Nothing here may be assumed to work until a spike confirms it on the target macOS version.** Items marked `UNVERIFIED` are hypotheses from general knowledge and web search on 2026-10-17.

Verification record format (append to the spike log at the bottom): macOS version, hardware, command or code, observed result, date.

## Platform constraints

- App is **not sandboxed** (ADR-006). Hardened runtime enabled for notarization.
- Sending Apple Events to other apps (System Events) requires `NSAppleEventsUsageDescription` in `Info.plist` and, under hardened runtime, the `com.apple.security.automation.apple-events` entitlement (`UNVERIFIED` exact requirements). The user is prompted once per target app (Automation permission).
- No Accessibility permission should be required. If a design needs it, stop and record a decision first.
- The global hotkey uses a Carbon-registered hotkey through the `KeyboardShortcuts` package. This normally needs no Accessibility permission (`UNVERIFIED` on the target version).

## Actions

### Desktop icons (global)
Mechanism (verified, S5): `defaults write com.apple.finder CreateDesktop -bool false`, then `killall Finder`. launchd relaunches Finder by itself; no other restart is needed. Restore: write the captured value, or `defaults delete com.apple.finder CreateDesktop` if the key was absent, then `killall Finder`.
Notes: capture must distinguish "key absent" from "true"; on the test Mac the key was absent by default, and deleting it restored the domain exactly (S5). Measured: icons gone 0.10 and 0.12 s after the command (2 runs), back after 0.30 to 0.59 s (5 runs) (S5). Two open Finder windows reopened on the same folders (S5, one run); other window states (minimized, full screen, on another Space, unsaved Get Info panels) are `UNVERIFIED`, not tested in M0. ADR-010 accepts the Finder flicker.
Run through `ProcessRunner` with an argv array.

### Dock auto-hide (global)
Candidate mechanism A: System Events AppleScript, `tell application "System Events" to set autohide of dock preferences to true`. Restore to the captured value. No Dock restart expected.
Candidate mechanism B: `defaults write com.apple.dock autohide -bool true` plus `killall Dock`.
Decision: prefer A if the spike confirms it is immediate and reliable. `UNVERIFIED`.

### Menu bar auto-hide (global)
Candidate mechanism: global preference `_HIHideMenuBar` in `NSGlobalDomain` and/or the System Events/appearance-related preference; behavior on current macOS (including newer versions with "Automatically hide and show the menu bar" options for full screen / always) is `UNVERIFIED`. The spike must determine: which key, whether it applies live or needs relaunch of `SystemUIServer`/logout, and the exact value domain. If no live-applying mechanism exists, the action is dropped from v1 and the decision is recorded.

### Hide apps
Mechanism: `NSWorkspace.shared.runningApplications` filtered by `activationPolicy == .regular`, excluded: this app, the frontmost app at activation, and the profile's exclusion list. `NSRunningApplication.hide()`. Snapshot: bundle identifiers that were visible (`isHidden == false`) and that this app hid. Restore: `unhide()` for those still running and still hidden.
Edge cases: apps that refuse to hide; full-screen apps; apps launched during the session (not touched).

### Wallpaper (per display)
Mechanism: `NSWorkspace.shared.setDesktopImageURL(_:for:options:)` for each `NSScreen`. Snapshot: `desktopImageURL(for:)` and `desktopImageOptions(for:)` per screen, keyed by a stable display identifier. Solid colors are rendered to a PNG in Application Support and applied as an image.
`UNVERIFIED`: behavior with multiple Spaces (setting may apply only to the current Space), with dynamic/system wallpapers (URL may be a bundle path or provider), with displays that connect or disconnect mid-session, and on the lock screen.
Stable display key: candidate is the display UUID from `CGDisplayCreateUUIDFromDisplayID`; verify.

### Focus / Do Not Disturb (open, ADR-013)
There is no public API to toggle Focus (Apple Developer Forums thread 729475, web search 2026-10-17). The only known path is running a user-installed Shortcut with `shortcuts run "<name>"` (`ProcessRunner`). Consequences: one manual onboarding step (user installs a Shortcut), no reliable way to read the previous Focus state `UNVERIFIED`, and fragility across macOS releases. The decision on whether to ship this in v1.0, v1.1, or never is made after spike S3.

## Launch at login
`SMAppService.mainApp.register()` / `unregister()` (macOS 13+). Status read from `SMAppService.mainApp.status`; the UI reflects the real status, including `requiresApproval`.

## Spikes (M0)

Each spike is a throwaway script or tiny Swift file that is **not** merged into `main` as product code. M0 kept its throwaway work outside the repository in `$HOME/presenter-spikes/` (prompt `docs/prompts/01-m0-platform-spikes.md`). Results are recorded here and a script may be committed under `Scripts/spikes/` only if it documents a verified fact and is lint-clean.

| ID | Question | Pass condition |
|---|---|---|
| S1 | Menu bar hide: which mechanism applies live, and how is it reverted? | Reproducible hide and restore without logout; key and domain recorded |
| S2 | Wallpaper: does `setDesktopImageURL` cover all Spaces and all displays; how are original wallpapers captured and restored (incl. dynamic wallpapers)? | Original wallpaper identical after restore on a multi-Space setup |
| S3 | Focus via `shortcuts run`: can a Shortcut be installed with one click; can previous state be read; latency | Documented verdict: ship / defer / drop |
| S4 | Dock autohide via System Events vs `defaults`+`killall`: immediacy, permission prompt text, entitlement needed | Chosen mechanism with evidence |
| S5 | Desktop icons: Finder restart side effects, key-absent handling | Restore leaves `defaults read` output identical to the start |
| S6 | Hotkey: `KeyboardShortcuts` on macOS 14/15/26 without extra permissions | Works with hardened runtime, unsigned and ad-hoc signed |

## Verified build facts

- **Ad-hoc signing does not apply the hardened runtime.** With `ENABLE_HARDENED_RUNTIME = YES` and `CODE_SIGN_IDENTITY = -`, Xcode runs `codesign --force --sign - --entitlements ... --timestamp=none --generate-entitlement-der` without `--options runtime`, and `codesign -dvv` shows `flags=0x2(adhoc)` only. The setting takes effect once a real signing identity is used (ADR-022). Verified 2026-10-17, macOS 27.0 (26A428), Xcode 27.1 (27A9275).
- **`LocalizedStringResource` with an interpolated `defaultValue` resolves through the catalog key.** `LocalizedStringResource("menu.version", defaultValue: "Version \(version)", ...)` uses the catalog's `%@` format for the requested locale: a throwaway script against the built app printed `Версия 0.1.0` for `ru` and `Version 0.1.0` for `en`. Verified 2026-10-17, same system.
- **A menu-bar-only app with `INFOPLIST_KEY_LSUIElement = YES` runs as a UI element.** `lsappinfo info -only ApplicationType` reported `type="UIElement"` for the built app, so it has no Dock icon. Verified 2026-10-17, same system.

## Spike log

Entries are `### S<ID> <date> macOS <version>`. Each line is labelled **machine** (command output, exit code, measured time) or **human** (what the user saw and reported in the session). Test system for every M0 entry unless stated otherwise: macOS 27.0 (26A428), Mac17,9 (Apple M5 Pro), one display (built-in Liquid Retina XDR, 3024 x 1964), Xcode 27.1 (27A9275). Every spike started from a backup of the five preference domains and the wallpaper state, and its baseline was compared with `defaults export <domain> -` converted to XML.

### S5 2026-10-17 macOS 27.0
- Baseline, machine: `defaults read com.apple.finder CreateDesktop` exited 1, key absent.
- Apply, machine: `defaults write com.apple.finder CreateDesktop -bool false; killall Finder`. `defaults read-type` reports `boolean`, value `0`. Finder came back under a new PID in 0.13 s without any further command. The Finder window at the desktop-icon window level (`CGWindowLevelForKey(.desktopIconWindow)`, read with `CGWindowListCopyWindowInfo`) disappeared: icons gone in 0.10 and 0.12 s (runs 4 and 5). Runs 2 and 3 timed out waiting for Finder windows the user had closed, so they have no hide timing.
- Apply, human: desktop icons gone. Two Finder windows open on different folders before the restart reopened on the same folders (1 run).
- Restore, machine: `defaults delete com.apple.finder CreateDesktop; killall Finder`. Key absent again; desktop-icon window back in 0.59, 0.31, 0.33, 0.30, 0.32 s (5 runs).
- Diff, machine: in runs 2 to 5 the key-by-key comparison of `com.apple.finder` before and after was empty, and the other four domains and the wallpaper state were unchanged. In run 1 `FXRecentFolders` changed order (the folder `project` moved to the top). The run stopped, the domain was re-imported from the baseline with `defaults import`, and the diff against the backup was empty. The reorder did not recur in runs 2 to 5 without user interaction with Finder windows, so it is attributed to the user clicking a Finder window during the check, not to the restart. This attribution is an inference, not observed directly.
- Verdict: **pass**. `killall Finder` is enough; restore must delete an absent key; window survival is verified only for two plain windows.
