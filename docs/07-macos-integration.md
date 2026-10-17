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
Mechanism: `defaults write com.apple.finder CreateDesktop -bool false`, then restart Finder (`killall Finder`). Restore: write the captured value, or delete the key if it did not exist, then restart Finder.
Notes: capture must distinguish "key absent" from "true". Finder windows reopen after restart (`UNVERIFIED` for all window states). ADR-010 accepts the Finder flicker.
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

Each spike is a throwaway script or tiny Swift file in `Scripts/spikes/` that is **not** merged into `main` as product code. Results are recorded here and the script may be kept under `Scripts/spikes/` only if it documents a verified fact and is lint-clean.

| ID | Question | Pass condition |
|---|---|---|
| S1 | Menu bar hide: which mechanism applies live, and how is it reverted? | Reproducible hide and restore without logout; key and domain recorded |
| S2 | Wallpaper: does `setDesktopImageURL` cover all Spaces and all displays; how are original wallpapers captured and restored (incl. dynamic wallpapers)? | Original wallpaper identical after restore on a multi-Space setup |
| S3 | Focus via `shortcuts run`: can a Shortcut be installed with one click; can previous state be read; latency | Documented verdict: ship / defer / drop |
| S4 | Dock autohide via System Events vs `defaults`+`killall`: immediacy, permission prompt text, entitlement needed | Chosen mechanism with evidence |
| S5 | Desktop icons: Finder restart side effects, key-absent handling | Restore leaves `defaults read` output identical to the start |
| S6 | Hotkey: `KeyboardShortcuts` on macOS 14/15/26 without extra permissions | Works with hardened runtime, unsigned and ad-hoc signed |

## Spike log

(empty; append entries as `### S<ID> <date> macOS <version>` with command, observation, verdict)
