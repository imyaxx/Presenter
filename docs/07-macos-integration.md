# macOS integration

How each system change is performed, what is verified, and what is not. **Nothing here may be assumed to work until a spike confirms it on the target macOS version.** Items marked `UNVERIFIED` are hypotheses from general knowledge and web search on 2026-10-17.

Verification record format (append to the spike log at the bottom): macOS version, hardware, command or code, observed result, date.

## Platform constraints

- App is **not sandboxed** (ADR-006). Hardened runtime enabled for notarization.
- Sending Apple Events to System Events from a hardened-runtime app requires both `NSAppleEventsUsageDescription` in `Info.plist` and the `com.apple.security.automation.apple-events` entitlement (verified, S4). Without either one there is no prompt: the call fails at once with error -1743, "Not authorized to send Apple events to System Events." With both, the user is prompted once per target app (Automation permission). An unanswered prompt makes the call fail after 120 s with error -1712, "AppleEvent timed out.", and the prompt closes. Permission is reset per bundle id with `tccutil reset AppleEvents <bundle id>`.
- No Accessibility permission should be required. If a design needs it, stop and record a decision first.
- The global hotkey uses a Carbon-registered hotkey through the `KeyboardShortcuts` package. This normally needs no Accessibility permission (`UNVERIFIED` on the target version).

## Actions

### Desktop icons (global)
Mechanism (verified, S5): `defaults write com.apple.finder CreateDesktop -bool false`, then `killall Finder`. launchd relaunches Finder by itself; no other restart is needed. Restore: write the captured value, or `defaults delete com.apple.finder CreateDesktop` if the key was absent, then `killall Finder`.
Notes: capture must distinguish "key absent" from "true"; on the test Mac the key was absent by default, and deleting it restored the domain exactly (S5). Measured: icons gone 0.10 and 0.12 s after the command (2 runs), back after 0.30 to 0.59 s (5 runs) (S5). Two open Finder windows reopened on the same folders (S5, one run); other window states (minimized, full screen, on another Space, unsaved Get Info panels) are `UNVERIFIED`, not tested in M0. ADR-010 accepts the Finder flicker.
Run through `ProcessRunner` with an argv array.

### Dock auto-hide (global)
Mechanism A (verified, S4): System Events AppleScript, `tell application "System Events" to set autohide of dock preferences to true`. Applies immediately with the normal slide animation, no Dock restart (same Dock PID), call time 0.097 to 0.231 s once permission is granted. It writes `com.apple.dock autohide` at once. Needs Automation permission for System Events (see Platform constraints).
Mechanism B (verified, S4): `defaults write com.apple.dock autohide -bool <value>` plus `killall Dock`. Needs no permission. The Dock visibly reloads (blinks); new Dock process in 0.09 to 0.30 s.
Key absent (verified, S4): an absent `autohide` key means the Dock is always shown, and System Events reports `false`. A can only write `true` or `false`, so restoring an absent key with A leaves an explicit `autohide = 0`. Following A's write of `false` with `defaults delete com.apple.dock autohide` restores the absent key exactly, without a Dock restart.
Decision: A, plus `defaults delete` when the captured key was absent (ADR-025).

### Menu bar auto-hide (global)
Mechanism (verified, S1): System Settings > Control Center > "Automatically hide and show the menu bar" is stored in three keys:

| UI value | `com.apple.controlcenter AutoHideMenuBarOption` | `NSGlobalDomain _HIHideMenuBar` | `NSGlobalDomain AppleMenuBarVisibleInFullscreen` |
|---|---|---|---|
| Always | 0 | true | false |
| On Desktop Only | 1 | true | true |
| In Full Screen Only | 2 | false | false |
| Never | 3 | absent in the test (not written by the UI) | true |
| Never changed (factory) | absent | absent | absent |

All three keys absent behaves as "In Full Screen Only". Choosing a value in the UI writes explicit values, so choosing the original value in the UI does not restore absent keys.
Writing the keys does not apply them on its own, not even after `killall ControlCenter` or `killall SystemUIServer`. Writing them and then posting the distributed notification `AppleInterfaceMenuBarHidingChangedNotification` applies the change live, without a process restart or logout. This works from a command-line process and from a hardened-runtime app with no entitlements, with no permission prompt. `_HIHideMenuBar` alone decides desktop hiding, but System Settings displays `AutoHideMenuBarOption`, so all three keys are written together to keep the UI truthful.
Apply: write the "Always" row, then post the notification. Restore: write the captured values, or delete each key that was absent, then post the notification (ADR-026).
`UNVERIFIED`: the notification name is not documented by Apple, and the posting side of System Settings was not observed (a `DistributedNotificationCenter` observer for all names received nothing on macOS 27.0, see S1). It may change in a future macOS release. Behavior on macOS 14 and 15 is untested.

### Hide apps
Mechanism: `NSWorkspace.shared.runningApplications` filtered by `activationPolicy == .regular`, excluded: this app, the frontmost app at activation, and the profile's exclusion list. `NSRunningApplication.hide()`. Snapshot: bundle identifiers that were visible (`isHidden == false`) and that this app hid. Restore: `unhide()` for those still running and still hidden.
Edge cases: apps that refuse to hide; full-screen apps; apps launched during the session (not touched).

### Wallpaper (per display)
Apply (verified, S2): `NSWorkspace.shared.setDesktopImageURL(_:for:options:)` with a generated solid-color PNG works, but only for the **current Space** of that screen. Other Spaces keep their wallpaper.
Capture through `desktopImageURL(for:)` and `desktopImageOptions(for:)` is **not reliable** (verified, S2). For a color wallpaper and for a dynamic wallpaper (provider `com.apple.wallpaper.choice.sequoia`) the API reports `file:///System/Library/CoreServices/DefaultDesktop.heic` with empty options, and restoring that puts up the default macOS image. For a still image file it reports the file URL and options; restoring it looks identical, but the stored entry changes from `linked` to `individual` and keeps the temporary image's fill color.
Capture source (verified, S2): `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`. It holds a `Displays` entry per display, keyed by the UUID from `CGDisplayCreateUUIDFromDisplayID`, and a `Spaces` entry per Space UUID plus an empty-string key, each with a provider (`com.apple.wallpaper.choice.color`, `.image`, `.sequoia`, ...), a configuration and encoded options as nested binary plists. Copying a captured `Index.plist` back and running `killall WallpaperAgent` restored a custom color and a dynamic wallpaper exactly, on both Spaces. Side effect: on relaunch `WallpaperAgent` added about 70 Aerial thumbnails to `aerials/thumbnails/` (cache). The store also keeps entries for Spaces that no longer exist and gains one per new Space or full-screen app (36 to 41 during this session), so restoring a whole-file copy also drops entries created during the session.
Stable display key: the `CGDisplayCreateUUIDFromDisplayID` UUID is the key the system itself uses in `Index.plist` (S2). Its stability across reboot and reconnection is `UNVERIFIED`, not testable in M0.
`UNVERIFIED`, not tested in M0: a second display (only one available); applying a wallpaper to all Spaces at once (no tested mechanism: the API changes only the current Space, and writing a synthesized `Index.plist` was not tested); displays connecting or disconnecting mid-session; the lock screen; behavior on macOS 14 and 15. `Index.plist` and the `WallpaperAgent` restart are undocumented and may change between macOS releases (ADR-027).

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

### S4 2026-10-17 macOS 27.0
- Baseline, machine: `defaults read com.apple.dock autohide` = `1`; the Dock was already auto-hidden, so each mechanism was tested by turning auto-hide off and back on.
- B, machine: `defaults write com.apple.dock autohide -bool false; killall Dock`, new Dock PID after 0.09 s; restore with `-bool true; killall Dock`, 0.30 s. Key diff of `com.apple.dock` against the baseline: none.
- B, human: the Dock became permanently visible with a visible reload (blink), and was auto-hidden again after restore.
- B key absent, machine: `defaults delete com.apple.dock autohide; killall Dock` as the starting state; apply `-bool true` wrote `1`; restore with `defaults delete` plus `killall Dock` left the key absent, key diff none. Human: with the key absent the Dock is permanently visible.
- A setup, machine: throwaway app bundles in `$HOME/presenter-spikes/s4-app/`, a Swift executable calling `NSAppleScript.executeAndReturnError`, signed `codesign --force --options runtime --sign - --entitlements <file>`, `codesign -dvv` shows `flags=0x10002(adhoc,runtime)`. Three bundle ids: `dev.imyaxx.presenter.spike.dock-full` (entitlement and usage description), `...dock-noent` (no entitlement), `...dock-nousage` (no usage description).
- A permission, human (from the user's screenshot): prompt text, bold, "“dock-full” wants access to control “System Events”. Allowing control will provide access to documents and data in “System Events”, and to perform actions within that app." Second line, the usage description: "Spike dock-full changes the Dock auto-hide setting." Buttons: "Don’t Allow", "Allow", and a help button.
- A permission, machine: an unanswered prompt failed the call after 120.213 s with -1712 "AppleEvent timed out." and the prompt closed. `dock-noent` and `dock-nousage` failed in 0.119 and 0.117 s with -1743 "Not authorized to send Apple events to System Events."; human: no prompt appeared for either.
- A apply, machine: `set autohide of dock preferences to false` then `true`: calls took 0.108, 0.100, 0.231, 0.109, 0.097 s (5 runs), the Dock PID did not change, and `defaults read com.apple.dock autohide` followed each call immediately. Human: the Dock slid in and out with the normal animation, no reload.
- A key absent, machine: with the key absent, `get autohide of dock preferences` returned `false`; setting `true` then the captured `false` left `autohide = 0` (key diff: `autohide: <absent> -> False`). A following `defaults delete com.apple.dock autohide` without a Dock restart made the key diff empty, and System Events still returned `false`.
- Final, machine: the `com.apple.dock` key diff and the full diff against the S4 baseline and the original backup were empty. Human: the Dock is auto-hidden as before.
- Verdict: **pass**. A is immediate and smooth and needs the entitlement, the usage description and one Automation prompt. B needs no permission but reloads the Dock. Restore of an absent key needs `defaults delete` with either mechanism.

### S1 2026-10-17 macOS 27.0
- Baseline, machine: `_HIHideMenuBar`, `AppleMenuBarVisibleInFullscreen` (`NSGlobalDomain`) and `AutoHideMenuBarOption` (`com.apple.controlcenter`) all absent. Human: System Settings shows "In Full Screen Only".
- Key discovery, machine: every user and `-currentHost` preference domain was exported before and after the user set each UI value. Key-level diff: Never set `AppleMenuBarVisibleInFullscreen` absent -> true and `AutoHideMenuBarOption` absent -> 3; On Desktop Only set `_HIHideMenuBar` absent -> true and the option 3 -> 1; Always set `AppleMenuBarVisibleInFullscreen` true -> false and the option 1 -> 0; In Full Screen Only set `_HIHideMenuBar` true -> false and the option 0 -> 2. All other changed keys belonged to background daemons (`ContextStoreAgent`, `spotlightknowledged`, `xpc.activity2`, `searchpartyuseragent`) or the System Settings window frame. Human: with Always the menu bar was hidden and appeared at the top edge.
- UI round trip, machine: returning to In Full Screen Only in the UI left explicit `false`, `false`, `2` where the keys had been absent, so the diff against the baseline was not empty. The three keys were deleted, the diff became empty, and the user saw the original behavior with the UI still on "In Full Screen Only".
- Refresh, human: after `defaults write` of the Always row the menu bar stayed visible; it stayed visible after `killall ControlCenter` (new PID) and after `killall SystemUIServer` (new PID).
- Notification discovery, machine: a throwaway `DistributedNotificationCenter` observer with `forName: nil` logged no notifications while the user toggled the setting, and also none for a notification it posted to itself (2 attempts). Observing all names is not usable on this version, so the notification name used next came from memory, not from observation.
- Notification, human: after `defaults write` of the Always row and posting `AppleInterfaceMenuBarHidingChangedNotification` from a command-line process, the menu bar hid on the desktop and in a full-screen app. After deleting the three keys and posting again, it was visible on the desktop and hidden in full screen (original behavior); machine: diff against the baseline empty.
- Minimal key, human: writing only `_HIHideMenuBar = true` and posting hid the menu bar on the desktop while System Settings still showed "In Full Screen Only".
- App, machine and human: a throwaway app `dev.imyaxx.presenter.spike.menubar`, signed `--options runtime` with no entitlements, wrote the keys with `CFPreferencesSetValue` and `CFPreferencesSynchronize` (both returned true) and posted the notification. Human: the menu bar hid with no permission prompt. The app's restore (keys set to nil, notification posted) gave an empty diff against the baseline and the original backup. Human: original behavior and UI value.
- Not measured: time from post to visible change (visual only, no machine signal).
- Verdict: **pass**. A live mechanism exists: three keys plus a distributed notification, with no permission. It relies on an undocumented notification name, so the risk is recorded in ADR-023.

### S2 2026-10-17 macOS 27.0
- Setup, human: two Spaces on the one built-in display, the user on Space 1. A second display was not available, so multi-display behavior is untested.
- Baseline, machine: the wallpaper was a custom color. In `Index.plist` the provider was `com.apple.wallpaper.choice.color`, configuration `customColor`, components 0.0823 (about `#151515`), on both Spaces. `desktopImageURL(for:)` returned `file:///System/Library/CoreServices/DefaultDesktop.heic` and `desktopImageOptions(for:)` returned empty options. The store held 41 Space entries, 36 at the start of the session.
- Apply, machine: `setDesktopImageURL` with a generated 64 x 64 solid-blue PNG and empty options succeeded. Afterwards the API reported the PNG with scaling 3, clipping 1 and a fill color. In `Index.plist` only `Displays[<display UUID>]` and `Spaces[""]` changed (to `individual`, provider `com.apple.wallpaper.choice.image`); no Space-UUID entry changed. Human: Space 1 blue, Space 2 still dark gray.
- API restore, machine and human: `setDesktopImageURL` with the captured `DefaultDesktop.heic` and empty options succeeded, but the user saw the default macOS image instead of the gray color.
- Store restore, machine: copying the baseline `Index.plist` back and running `killall WallpaperAgent` (new PID). Decoded store content equal to the baseline except `LastUse` timestamps; the five preference domains unchanged; the file listing of `com.apple.wallpaper/` unchanged except about 70 PNG files added under `aerials/thumbnails/`. The user chose to keep them as regenerated cache. Human: Space 1 dark gray, Space 2 dark gray.
- Still image, machine: after the user chose a still photo (`file:///Users/imya/Downloads/...jpg`) the API returned that URL with scaling 3 and clipping 1. An API round trip (capture, blue for 5 s, restore) brought the same file back, but the stored entry changed from `linked` to `individual` and its options now held the blue fill color. Human: looked identical to before.
- Dynamic wallpaper, machine: with a dynamic wallpaper chosen (store provider `com.apple.wallpaper.choice.sequoia`) the API returned `DefaultDesktop.heic` and empty options. After an API round trip the store held a plain image entry for `DefaultDesktop.heic`. Human: a different image than the one chosen.
- Dynamic wallpaper, store restore: the user re-selected it, the store was copied, blue was applied through the API for 5 s, and the copy was put back with `killall WallpaperAgent`. Machine: decoded store equal to the copy except `LastUse`. Human: the dynamic wallpaper was back and still selected.
- Final, machine: the baseline `Index.plist` was copied back and `WallpaperAgent` restarted. Store content equal to the S2 baseline except `LastUse`; listing outside `aerials/thumbnails/` identical; preference domains unchanged. Human: both Spaces dark gray, the color selected in System Settings.
- Verdict: **pass with design change**. Apply with `setDesktopImageURL` reaches only the current Space. Capture and restore must use the `Index.plist` store plus a `WallpaperAgent` restart, not the NSWorkspace getters. Not covered: multiple displays, all Spaces at once, macOS 14 and 15.
