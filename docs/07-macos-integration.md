# macOS integration

How each system change is performed, what is verified, and what is not. **Nothing here may be assumed to work until a spike confirms it on the target macOS version.** Items marked `UNVERIFIED` are hypotheses from general knowledge and web search on 2026-10-17.

Verification record format (append to the spike log at the bottom): macOS version, hardware, command or code, observed result, date.

## Platform constraints

- App is **not sandboxed** (ADR-006). Hardened runtime enabled for notarization.
- Sending Apple Events to System Events from a hardened-runtime app requires both `NSAppleEventsUsageDescription` in `Info.plist` and the `com.apple.security.automation.apple-events` entitlement (verified, S4). Without either one there is no prompt: the call fails at once with error -1743, "Not authorized to send Apple events to System Events." With both, the user is prompted once per target app (Automation permission). An unanswered prompt makes the call fail after 120 s with error -1712, "AppleEvent timed out.", and the prompt closes. Permission is reset per bundle id with `tccutil reset AppleEvents <bundle id>`.
- The app carries both since `feat/platform-adapters`. The entitlement is in `Presenter.entitlements`; the usage description comes from `project.yml` and is localized in English and Russian through `InfoPlist.xcstrings`. Both were verified on the built app, but have not yet been exercised against System Events.
- `NSAppleScriptRunner` runs scripts on one dedicated background thread, never on the main thread (ADR-040). The SDK header states no thread requirement. Whether this works for Apple events to System Events and with the Automation prompt is `UNVERIFIED` (see "Verified in M2 branch 1").
- No Accessibility permission should be required. If a design needs it, stop and record a decision first.
- The global hotkey uses `KeyboardShortcuts` 3.1.0 (MIT, revision `772133d9dbe800fdac0473226822994c5c162c58`, released 2026-09-11, repository not archived). On macOS 27.0 it registered and fired with no Accessibility or Input Monitoring prompt, ad-hoc signed with and without the hardened runtime, including while another app was frontmost in full screen (verified, S6). macOS 14 and 15 are untested. The package persists the shortcut in the app's own defaults domain as `KeyboardShortcuts_<name>`.

## Actions

### Desktop icons (global)
Mechanism (verified, S5): `defaults write com.apple.finder CreateDesktop -bool false`, then `killall Finder`. launchd relaunches Finder by itself; no other restart is needed. Restore: write the captured value, or `defaults delete com.apple.finder CreateDesktop` if the key was absent, then `killall Finder`.
Notes: capture must distinguish "key absent" from "true"; on the test Mac the key was absent by default, and deleting it restored the domain exactly (S5). Measured: icons gone 0.10 and 0.12 s after the command (2 runs), back after 0.30 to 0.59 s (5 runs) (S5). Two open Finder windows reopened on the same folders (S5, one run); other window states (minimized, full screen, on another Space, unsaved Get Info panels) are `UNVERIFIED`, not tested in M0. ADR-010 accepts the Finder flicker.
Run through `ProcessRunner` with an argv array.
Implemented in ModeKit as `DesktopIconsAction` against the `DefaultsStore` and `ProcessRunner` ports (M1). In-app `CFPreferences` access to the `com.apple.finder` domain is `UNVERIFIED`: S1 verified `CFPreferences` only for the Control Center and global domains; the M2 adapter `CFPreferencesDefaultsStore` uses `CFPreferences` for it; `feat/adapter-check-tool` verifies it, and if it fails the replacement is the `defaults` tool through `ProcessRunner`. `killall` exit codes are taken from `man killall` on macOS 27.0 ("exits 0 if some processes have been found and signalled successfully. Otherwise, a status of 1 will be returned."), not observed: exit 1 (no Finder, or not signalled) is treated as success (ADR-035), and exit 1 on a running system is `UNVERIFIED`.
Adapter check 2026-10-20, macOS 27.0.1: the in-app `CFPreferences` read and write of `com.apple.finder` work, `killall Finder` exited 0 on every run, and icons hid and returned (C1, C3). Exit 1 was seen only for a name that matches no process (C2).

### Dock auto-hide (global)
Mechanism A (verified, S4): System Events AppleScript, `tell application "System Events" to set autohide of dock preferences to true`. Applies immediately with the normal slide animation, no Dock restart (same Dock PID), call time 0.097 to 0.231 s once permission is granted. It writes `com.apple.dock autohide` at once. Needs Automation permission for System Events (see Platform constraints).
Mechanism B (verified, S4): `defaults write com.apple.dock autohide -bool <value>` plus `killall Dock`. Needs no permission. The Dock visibly reloads (blinks); new Dock process in 0.09 to 0.30 s.
Key absent (verified, S4): an absent `autohide` key means the Dock is always shown, and System Events reports `false`. A can only write `true` or `false`, so restoring an absent key with A leaves an explicit `autohide = 0`. Following A's write of `false` with `defaults delete com.apple.dock autohide` restores the absent key exactly, without a Dock restart.
Decision: A, plus `defaults delete` when the captured key was absent (ADR-025).
Implemented in ModeKit as `DockAction` against the `AppleScriptRunner` and `DefaultsStore` ports (M1). In-app `CFPreferences` access to the `com.apple.dock` domain is `UNVERIFIED`: S1 verified `CFPreferences` only for the Control Center and global domains; the M2 adapter `CFPreferencesDefaultsStore` uses `CFPreferences` for it; `feat/adapter-check-tool` verifies it, and if it fails the replacement is the `defaults` tool through `ProcessRunner`.
Adapter check 2026-10-20, macOS 27.0.1: the in-app `CFPreferences` read and write of `com.apple.dock` work. The System Events script runs from the runner's background thread, and the real prompt, Allow and Don't Allow (-1743) all behave as described (C4). An unanswered prompt now ends with -609 "Connection is invalid" after 120 s, not -1712 (C4).

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
Implemented in ModeKit as `MenuBarAction` against the `DefaultsStore` and `DistributedNotifier` ports (M1, ADR-037). The global domain is the string `NSGlobalDomain` in a `DefaultsKey`; the M2 adapter maps it to the global preferences domain. S1 verified `CFPreferencesSetValue` and `CFPreferencesSynchronize` for these three keys from a throwaway hardened-runtime app with no entitlements (`dev.imyaxx.presenter.spike.menubar`); the M2 adapter keeps that route. Reading the keys back through `CFPreferences` from the real app is `UNVERIFIED`. `post` cannot report whether macOS reacted, so the action cannot verify the live effect; the three keys are verified by reading them back in tests only.
Adapter check 2026-10-20, macOS 27.0.1: reading and writing the three keys from the real app and posting the notification from the real app hid the menu bar and restored it (C5).

### Hide apps
Mechanism: `NSWorkspace.shared.runningApplications` filtered by `activationPolicy == .regular`, excluded: this app, the frontmost app at activation, and the profile's exclusion list. `NSRunningApplication.hide()`. Snapshot: bundle identifiers that were visible (`isHidden == false`) and that this app hid. Restore: `unhide()` for those still running and still hidden.
Edge cases: apps that refuse to hide; full-screen apps; apps launched during the session (not touched).
`UNVERIFIED`: no M0 spike covers this action (S1 to S6 do not include it). Verify it in M2 against the per-action manual QA checklist before relying on it.
Implemented in ModeKit as `HideAppsAction` and `HideAppsRestorer` against the `WorkspaceAdapter` port (M1, ADR-036), with the mechanism above as the M2 adapter's plan. The port's `changed` means the request was accepted, not that the application was seen hidden: `NSRunningApplication.hide()` is asynchronous. Still `UNVERIFIED`, none of it run on a real system: the effect and timing of `NSRunningApplication.hide()` and `unhide()` and their return values; several running instances of one bundle identifier (the port hides and unhides every instance, and the action treats them as one candidate); full-screen applications; which applications refuse to hide.
Adapter check 2026-10-20, macOS 27.0.1: hiding and unhiding work, including several instances. The `Bool` that `hide()` returns is not reliable, so the adapter observes `isHidden` (C6, fixed). A full-screen application is marked hidden, but its full-screen Space keeps its window, so the effect is not visible (C6).

### Wallpaper (per display)
Apply (verified, S2): `NSWorkspace.shared.setDesktopImageURL(_:for:options:)` with a generated solid-color PNG works, but only for the **current Space** of that screen. Other Spaces keep their wallpaper.
Capture through `desktopImageURL(for:)` and `desktopImageOptions(for:)` is **not reliable** (verified, S2). For a color wallpaper and for a dynamic wallpaper (provider `com.apple.wallpaper.choice.sequoia`) the API reports `file:///System/Library/CoreServices/DefaultDesktop.heic` with empty options, and restoring that puts up the default macOS image. For a still image file it reports the file URL and options; restoring it looks identical, but the stored entry changes from `linked` to `individual` and keeps the temporary image's fill color.
Capture source (verified, S2): `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`. It holds a `Displays` entry per display, keyed by the UUID from `CGDisplayCreateUUIDFromDisplayID`, and a `Spaces` entry per Space UUID plus an empty-string key, each with a provider (`com.apple.wallpaper.choice.color`, `.image`, `.sequoia`, ...), a configuration and encoded options as nested binary plists. Copying a captured `Index.plist` back and running `killall WallpaperAgent` restored a custom color and a dynamic wallpaper exactly, on both Spaces. Side effect: on relaunch `WallpaperAgent` added about 70 Aerial thumbnails to `aerials/thumbnails/` (cache). The store also keeps entries for Spaces that no longer exist and gains one per new Space or full-screen app (36 to 41 during this session), so restoring a whole-file copy also drops entries created during the session.
Store structure, machine-observed read-only on 2026-10-18. Key names and value kinds only, from the live store of the development Mac (one display, a custom color, 44 Space entries) and the S2 copies.
- The top level is a dictionary with `AllSpacesAndDisplays` (string), `Displays` (dictionary keyed by display UUID), `Spaces` (dictionary keyed by Space UUID plus the empty-string key) and `SystemDefault` (dictionary).
- An entry has a `Type` string (`linked` or `individual`). A `linked` entry has a `Linked` dictionary. An `individual` entry, seen only in the S2 copy with a dynamic wallpaper, has `Desktop` and `Idle` dictionaries instead.
- Each of `Linked`, `Desktop` and `Idle` holds:
  - `Content`, with `Choices` (an array of dictionaries with `Configuration` data, `Files` array and `Provider` string), `EncodedOptionValues` data and `Shuffle` string;
  - `LastSet` and `LastUse` dates.
- `Configuration` is a nested binary property list for color and image choices: `type` (`customColor`, `systemColor`, `imageFile`), plus `url.relative` for an image. For `com.apple.wallpaper.choice.sequoia` it is empty data.
- `EncodedOptionValues` is a nested binary property list with `values`, holding the color components and a nested color-space property list, and, for the dynamic wallpaper, `placement`.
- Each entry of `Spaces` holds `Default` and `Displays`, shaped like the entries above.

Not observed as a property list: the store right after an apply of a custom image or a solid color. S2 kept only a text dump of that state, which shows `individual` entries with provider `com.apple.wallpaper.choice.image` under `Displays[<display UUID>]` and `Spaces[""]`. The check tool observes that state under backup, and may adjust the inspector (ADR-041).

The M2 adapters exist since `feat/platform-adapters` (`AppKitWorkspaceAdapter`, `CoreGraphicsSolidColorImageRenderer`, `PropertyListWallpaperStoreInspector`, `SystemLocations`). Their real effects are verified by `feat/adapter-check-tool`. Until then the `UNVERIFIED` items and the M2 obligations below remain open, except that the renderer is implemented and its output verified, and the display mapping round trip is verified on one display.

Stable display key: the `CGDisplayCreateUUIDFromDisplayID` UUID is the key the system itself uses in `Index.plist` (S2). Its stability across reboot and reconnection is `UNVERIFIED`, not testable in M0.
`UNVERIFIED`, not tested in M0: a second display (only one available); applying a wallpaper to all Spaces at once (no tested mechanism: the API changes only the current Space, and writing a synthesized `Index.plist` was not tested); displays connecting or disconnecting mid-session; the lock screen; behavior on macOS 14 and 15. `Index.plist` and the `WallpaperAgent` restart are undocumented and may change between macOS releases (ADR-027).
Implemented in ModeKit as `WallpaperAction` and `WallpaperRestorer` (M1, ADR-038, ADR-039), against these ports: `WorkspaceAdapter` (`connectedDisplays`, `setDesktopImage` on the current Space), `SolidColorImageRenderer`, `FileStore` (store bytes and `solid-rrggbb.png` in the generated images directory), `SessionClock`, `WallpaperStoreInspector` and `ProcessRunner`. ModeKit never parses `Index.plist`, never resolves the store path (injected as `WallpaperLocations`) and never uses `desktopImageURL`. Apply fingerprints the store before any change, sets the image, then polls the store every 100 ms, up to 50 times, until the fingerprint changes; otherwise it fails with `storeDidNotChange`. That includes the case where the target already is the current wallpaper. Restore writes the captured bytes atomically and runs `/usr/bin/killall WallpaperAgent` with a 10 s timeout. After a completed apply it does neither when the store already equals the snapshot, or when its fingerprint no longer equals the applied one (the user changed the wallpaper). After an interrupted apply (`applied: nil`, including the rollback of `storeDidNotChange`) it always writes and restarts, even when the bytes are equal: the image may be on screen before the agent persists it, and a late persist must be overwritten. Whether restarting the agent discards a change it has not yet persisted is `UNVERIFIED`.
`UNVERIFIED` for this implementation as of M1; all items below were settled by the adapter check on 2026-10-20 (C7, the table "Verified in M2 branch 2"), except a second display:
- The store format as the inspector will see it, including which fields are volatile.
- The latency between `setDesktopImageURL` and the store change. The 100 ms interval and 50 polls are engineering guesses, not measurements.
- Restoring through an atomic replace of `Index.plist` (temporary file and `rename(2)`, as `FileManagerFileStore` does) followed by `killall WallpaperAgent`. S2 used a plain copy.
- `killall WallpaperAgent` exit 1, read from the manual (ADR-035), not observed.
- Several Spaces, a full-screen Space and a second display.
- That `desktopImageURL` is needed nowhere.
M2 obligations for the wallpaper:
- Done in `feat/platform-adapters`:
  - The real `Index.plist` was inspected read-only, and `PropertyListWallpaperStoreInspector` is implemented with sanitized fixtures (ADR-041).
  - `SolidColorImageRenderer` is implemented.
  - Each `NSScreen` is mapped to its `CGDisplayCreateUUIDFromDisplayID` UUID (`DisplayIdentifierMapping`).
  - `desktopImageURL` is used nowhere in the code.
- Left for `feat/adapter-check-tool`:
  - Observe the store after a real apply, and check the inspector against it.
  - Measure the latency between `setDesktopImageURL` and the store change, and recalibrate the polling constants.
  - Verify that an atomic replace of `Index.plist` followed by `killall WallpaperAgent` restores correctly, and whether the restart discards an unpersisted change.
  - Test a second display, several Spaces and a full-screen Space.

### Focus / Do Not Disturb (ADR-013, proposed)
No public API toggles Focus (Apple Developer Forums thread 729475, from a web search on 2026-10-17; not re-checked). Mechanism (verified, S3): user-created Shortcuts run with `shortcuts run "<name>"` through `ProcessRunner`. "Set Focus: Turn Do Not Disturb On until Turned Off" and "Set Focus: Turn Do Not Disturb Off" each take 0.14 to 0.18 s (one Off outlier at 1.55 s) with no prompt. A missing Shortcut fails with exit 1 and "Couldn’t find shortcut" in 0.05 to 0.12 s.
Previous state (verified, S3): a Shortcut with "Get Current Focus" run with `--output-path` writes the active Focus name (`Do Not Disturb`) or nothing when no Focus is active, in 0.11 to 0.15 s. The first run while a Focus is active shows "Allow “<shortcut>” to output 1 focus?" (Don’t Allow / Allow Once / Always Allow) and blocks until it is answered (108 s in the test). After Always Allow it no longer prompts. The Focus database `~/Library/DoNotDisturb/` cannot be read without Full Disk Access ("Operation not permitted").
Distribution (blocked, S3): shipping a prebuilt `.shortcut` file was not possible from the test Mac. Export for "Anyone" requires an iCloud sign-in. The Share menu has no Export File item. Dragging the tile to Finder, `shortcuts sign`, and importing an unsigned file did not produce a usable file (attempts reported by the user). Whether importing a signed file needs iCloud on the receiving Mac is `UNVERIFIED`, because no signed file could be produced. The verified fallback is the user building the Shortcuts by hand (a few minutes, user report).

## Launch at login
`SMAppService.mainApp.register()` / `unregister()` (macOS 13+). Status read from `SMAppService.mainApp.status`; the UI reflects the real status, including `requiresApproval`. `UNVERIFIED`: not covered by an M0 spike; verify in M2.

## Verified in M2 branch 1 (`feat/platform-adapters`)

Machine-observed on the development Mac, macOS 27.0, Xcode 27.1, on 2026-10-18, by the app's unit tests and by read-only commands. No real setting was changed (ADR-040). Personal data is left out: no path, user name, display UUID or store content.

- **Display UUID mapping.** One `NSScreen` was connected. Its `NSScreenNumber`, taken through `CGDirectDisplayID` and `CGDisplayCreateUUIDFromDisplayID`, gave a UUID, and the same mapping found the same `NSScreen` again (round trip).
- **Process runner.**
  - `/usr/bin/true` exited 0 and `/usr/bin/false` exited 1. A missing executable failed at launch.
  - Arguments containing spaces, quotes, `;`, `$HOME` and `*` reached `/bin/test` verbatim.
  - `/bin/sleep` with a 300 ms timeout ended about 0.34 s after the call started, after SIGTERM.
  - A `/bin/sh` loop that ignores SIGTERM was killed with SIGKILL after the 2 s grace period.
  - Cancelling the caller stopped the child.
  - Afterwards, `pgrep -f` found none of these processes.
- **AppleScript error mapping, off the main thread.** These ran on the runner's dedicated background thread:
  - `error number -1743` mapped to `notAuthorized`, `error number -1712` to `timedOut`, and `error "boom" number 42` to `failed(code: 42, message: "boom")`.
  - A script that does not compile failed with `failed`.
  - Two `delay 0.4` scripts issued at once took at least 0.8 s, so they did not overlap.
  - The watchdog returned within 1.5 s for `delay 2` with a 300 ms timeout.
  - None of these scripts sends an Apple event to another application.
- **`CFPreferences` with a throwaway domain.**
  - `true`, `false`, 0, 1, 3 and -2 round-tripped with their types; 0 and 1 stayed integers.
  - A string and a floating-point value were rejected as unsupported.
  - A value written by `/usr/bin/defaults write` from another process was read after `CFPreferencesSynchronize`.
  - After the last key of a domain was removed and synchronized, cfprefsd rewrote the domain's plist file once, as an empty dictionary, 9.4 s and 10.9 s later in two runs, and then left it alone.
- **Distributed notifications.** A private name posted with `deliverImmediately: true` reached an observer for that name in the same process. In S1, an observer for all names (`forName: nil`) received nothing.
- **Renderer output.** `CoreGraphicsSolidColorImageRenderer` produced a PNG (signature `89 50 4E 47 0D 0A 1A 0A`), 64 x 64 pixels. Decoded with ImageIO and drawn into an sRGB bitmap, it gave the exact channel values for black, white, pure red, pure green, pure blue, `#151515` and `#1E90FF`.
- **Wallpaper store, untouched by the tests.** The live `Index.plist` was only read. Its SHA-256 differed between the start and the end of the branch's test runs. Its modification time was a single moment during one test run, and its newest timestamps were the `LastUse` values at that same second. No code in this branch writes the store. The most likely cause is `WallpaperAgent` refreshing `LastUse` by itself, which agrees with S2's finding that the store differs only in `LastUse` across an agent restart, but it is not attributed with certainty. It supports treating `LastUse` as volatile (ADR-041).
- **Property lists.** `PropertyListSerialization` accepts the bare bytes `bplist00` as an old-style text string, not as an error.
- **Built app.** With the commands quoted in the branch's PR:
  - The built `Info.plist` holds `NSAppleEventsUsageDescription`.
  - `codesign -d --entitlements` lists `com.apple.security.automation.apple-events = true`.
  - `en.lproj/InfoPlist.strings` and `ru.lproj/InfoPlist.strings` hold the English and Russian descriptions.
  - `codesign -dvv` still shows `flags=0x2(adhoc)`: the ad-hoc build has no hardened runtime flag (see Verified build facts).
- **`NSAppleScript` threading, from local evidence.** The SDK header (`NSAppleScript.h`, macOS 27.0 SDK) states no thread requirement and carries no main-actor annotation. The S4 throwaway app ran its scripts on the main thread only. So whether `NSAppleScript` sends Apple events to System Events correctly from a background thread, including when the Automation prompt is shown, is `UNVERIFIED`; the check tool exercises it.

## Verified in M2 branch 2 (adapter check, `feat/adapter-check-tool`)

Verdicts from the adapter check protocol (`docs/13-adapter-check.md`), run on 2026-10-20 on macOS 27.0.1 with the user present. Details are in the C-series entries of the spike log. Items still marked `UNVERIFIED` above are settled here:

| Item | Verdict |
|---|---|
| In-app `CFPreferences` for `com.apple.finder` and `com.apple.dock` | Verified, read and write (C1, C3, C4) |
| In-app `CFPreferences` for the three menu bar keys, and the notification posted from the real app | Verified (C1, C5) |
| `NSAppleScript` on a background thread sending Apple events to System Events | Verified (C4) |
| Real Automation prompt, English | Verified, text in C4. The prompt follows the system language, not `-AppleLanguages`. Russian not testable without changing the system language. |
| Denial (-1743) | Verified, mapped to `notAuthorized` (C4) |
| Unanswered prompt | **Corrected**: -609 "Connection is invalid" after 120 s, not -1712 (C4). Mapped to `failed(code: -609)`. The 130 s watchdog does not fire first. |
| `NSRunningApplication.hide()` and `unhide()` | Effect verified. The return value is **not reliable**: `hide()` returned false while the app hid. The adapter now observes `isHidden` (C6). |
| Several instances of one bundle identifier | Verified, all instances hidden and unhidden (C6) |
| Full-screen applications | Hidden state set and restored, but the full-screen Space keeps its window: no visible effect (C6) |
| `setDesktopImage` through the adapter | Verified, current Space only (C7) |
| Post-apply store structure and the inspector | Observed (C7). **Corrected**: the fingerprint now covers `Spaces[""]` only, because the agent rewrites `Displays` by itself (C7). |
| Polling latency | Median 153 ms, p95 161 ms; 50 polls kept (C7) |
| Atomic replace of `Index.plist` followed by `killall WallpaperAgent` | Verified, exact (C7, C8) |
| Whether the agent restart discards an unsaved change | It does (C7, interrupted apply) |
| `killall` exit codes | 0 for Finder and WallpaperAgent on every run; 1 when no process matches; found-but-unsignalled not testable (C2) |
| Second display | Untested: one display |
| Several Spaces | Verified for the wallpaper: other Spaces unchanged (C7) |
| Full-screen Space | Menu bar: no change, as expected (C5). Hide apps: see above. A full-screen Space adds a store entry (C5, C10). |
| Crash recovery from `session.json` after `kill -9` | Verified (C8) |
| The wallpaper fingerprint detecting a user's change | Verified (C9) |
| Reboot recovery, macOS 14 and 15 | Not tested (out of scope) |

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

### S6 2026-10-17 macOS 27.0
- Setup, machine: throwaway package `$HOME/presenter-spikes/s6-hotkey`, swift-tools-version 6.0, dependency `https://github.com/sindresorhus/KeyboardShortcuts` pinned `exact: "3.1.0"` (resolved revision `772133d9dbe800fdac0473226822994c5c162c58`; latest release per `gh api`, published 2026-09-11; not archived; MIT). An accessory-policy `NSApplication` registers the name `spike` with default Control-Option-Command-P and logs each `onKeyUp` with the frontmost bundle id. Two bundles: `dev.imyaxx.presenter.spike.hotkey-adhoc` signed `codesign --sign -` (`flags=0x2(adhoc)`), and `...hotkey-runtime` signed `--options runtime --sign -` (`flags=0x10002(adhoc,runtime)`).
- Permissions before, human: Input Monitoring listed 0 apps. Privacy & Security on macOS 27.0 has no row named "Accessibility" (the list goes from Reminders to App Management). No `hotkey-*` app appeared anywhere.
- Ad hoc, machine: `registered shortcut=⌃⌥⌘P`, then 5 `fired` lines, all with `frontmost=com.apple.finder`. Human: the user pressed the shortcut in a Finder window and in a full-screen app; no prompt. The log does not show which press was made in full screen.
- Hardened runtime, machine: `registered`, then `fired frontmost=com.apple.finder` and `fired frontmost=com.apple.Music`. Human: one press in a Finder window and one with Music in full screen; no prompt.
- Permissions after, human: Input Monitoring still 0 apps; no `hotkey-*` app in any privacy list.
- Side effect, machine: each spike app wrote `KeyboardShortcuts_spike = {"carbonKeyCode":35,"carbonModifiers":6400}` to its own defaults domain. The five tracked domains were unchanged except two keys. `FXRecentFolders` was reordered by the user's Finder use and re-imported from the backup. `NSGlobalDomain SLSMenuBarUseBlurredAppearance` was removed: the user confirmed changing a menu bar appearance option in System Settings during the session and chose to keep it.
- Not tested: macOS 14 and 15 (not available), the recorder UI, conflicts with system shortcuts.
- Verdict: **pass** on macOS 27.0. No extra permission is needed for registration or delivery, with or without the hardened runtime.

### S3 2026-10-17 macOS 27.0
- CLI, machine: `shortcuts help` lists the subcommands `run`, `list`, `view`, `sign` (modes `anyone`, `people-who-know-me`); there is no import or export subcommand. `shortcuts list` returned 0 shortcuts before the spike.
- Missing Shortcut, machine: `shortcuts run "Presenter Focus On"` before it existed: exit 1, stderr "Error: The operation couldn’t be completed. Couldn’t find shortcut", 0.12, 0.05, 0.05 s (3 runs).
- Focus store, machine: `ls ~/Library/DoNotDisturb/` and `ls ~/Library/DoNotDisturb/DB` returned "Operation not permitted". `com.apple.ncprefs` does not exist on this version.
- Build, human: the user created "Presenter Focus On" (Set Focus: Do Not Disturb On, until Turned Off), "Presenter Focus Off" (Set Focus: Do Not Disturb Off) and "Presenter Focus State" (Get Current Focus) by hand in Shortcuts; all actions existed. Baseline, human: no Focus active.
- Run, machine: On 0.24 s, then State took 108.12 s and output `Do Not Disturb`, Off 0.17 s, State 0.13 s with empty output; all exit 0. Human: the 108 s State run showed the prompt "Allow “Presenter Focus State” to output 1 focus?" with Do Not Disturb listed and the buttons Don’t Allow, Allow Once, Always Allow (user screenshot). The user chose Always Allow. The menu bar showed the Do Not Disturb moon while it was on.
- Latency, machine: 5 cycles of On, State, Off, State. On 0.16, 0.18, 0.16, 0.14, 0.14 s; State while on 0.15, 0.15, 0.14, 0.13, 0.14 s, output `Do Not Disturb`; Off 0.15, 0.16, 1.55, 0.14, 0.17 s; State while off 0.14, 0.12, 0.12, 0.11, 0.13 s, empty output. All exit 0, no prompt. Final state, machine: State returned empty output (no Focus). Human: Do Not Disturb off.
- Distribution, human (user report): Share has no Export File item. File > Export with "For: Anyone" shows "In order to do this, you must be signed into iCloud." Dragging the tile to Finder, `shortcuts sign`, and importing an unsigned file produced no usable file. The user declined an iCloud sign-in for the spike.
- Verdict: **pass** for running, latency, failure behavior and reading the previous state. **Blocked** for shipping a prebuilt `.shortcut` file: it needs an iCloud sign-in on the exporting Mac, which a dedicated project Apple Account would provide. Untested: whether importing needs iCloud on the receiving Mac, Focus modes other than Do Not Disturb, macOS 14 and 15. Decision in ADR-013.

### C0 2026-10-20 macOS 27.0.1 (adapter check B0, preconditions)
- Setup, machine: macOS 27.0.1 (26A434), the development Mac, one display (the built-in Retina; `system_profiler` shows no second display, mirroring off). Backup made with `Scripts/adapter-check-backup.sh`. Screenshot skipped: `screencapture` may ask for a privacy permission, which the protocol never requests.
- Setup, human: at least two Spaces on the display; TextEdit and Calculator may be opened and hidden; one app can be put in full screen. The user first reported two displays; the machine saw one, so second-display checks are untested.
- The user turned Dock auto-hide off for B4, after the first backup, and later switched the wallpaper to a dynamic one before B9. Both were their own changes, and working backups were taken after each. B10 restored the first backup.

### C1 2026-10-20 macOS 27.0.1 (B1, read parity)
- Machine: `world`, read through `CFPreferencesDefaultsStore` inside the app, equals `defaults read-type` and `defaults read` for all five keys: `com.apple.finder`, `com.apple.dock`, `com.apple.controlcenter` and two in the global domain. This included a Dock value changed in System Settings seconds earlier. The store SHA-256 from the tool equals `shasum -a 256`. Verdict: in-app `CFPreferences` **reads** of the Finder, Dock, Control Center and global domains work.

### C2 2026-10-20 macOS 27.0.1 (B2, `killall` exit codes)
- Machine: `killall` with a name that matches no process exits **1** ("No matching processes belonging to you were found").
- A process that is found but not signalled cannot be produced: `killall` only matches the user's own processes. That case is not testable here.
- `killall Finder` and `killall WallpaperAgent` exited **0** on every run of C3, C7 and C8 (machine, from the tool's process lines).

### C3 2026-10-20 macOS 27.0.1 (B3, desktop icons)
- Machine: `run --profile desktop-icons`, 8 s hold. The report shows `desktopIcons` restored; `killall Finder` exited 0 twice (apply and restore); the diff is empty.
- Human: in the first run the user was in a full-screen Space and did not see the desktop. In the repeat, the icons hid for about 8 s and came back.
- Verdict: the in-app `CFPreferences` **write** to `com.apple.finder`, the Finder restart through `FoundationProcessRunner`, and the restore all work.

### C4 2026-10-20 macOS 27.0.1 (B4, Dock and the Automation prompt)
Before each case, `tccutil reset AppleEvents <the app's bundle identifier>` was run for this app only.
- **Allow.**
  - Machine: `run --profile dock`; activation 4.0 s, including the human answer; `dock` restored; diff empty.
  - Human: the Dock hid and came back.
  - Verdict: `NSAppleScript` on the runner's background thread sends Apple events to System Events and the Automation prompt works.
- **Prompt text** (human, from a screenshot of the English prompt): title "“Presenter” wants access to control “System Events”. Allowing control will provide access to documents and data in “System Events”, and to perform actions within that app."; explanation "Presenter controls the Dock's auto-hide setting through System Events while a profile is active." (exactly our `NSAppleEventsUsageDescription`); buttons Don't Allow and Allow.
- **Don't Allow.**
  - Machine: -1743 was mapped to `notAuthorized`, logged as "Not authorized to send Apple events (-1743)".
  - The activation rolled back, the state is idle, no `session.json` remains, and the diff is empty.
- **`--language ru`.**
  - Human: the prompt was still in English. Machine: the system language order is English, then Russian.
  - The prompt is drawn by the system in the system language, not in the language the app was launched with.
  - The Russian prompt is not testable without changing the system language, which is out of scope. The Russian string is verified in the built bundle (M2 branch 1).
- **Prompt left unanswered.**
  - Machine: the activation failed after **120.03 s** with **-609, "System Events got an error: Connection is invalid."**, mapped to `failed(code: -609, …)`.
  - The rollback was clean and the diff empty. Human: the prompt closed by itself.
  - This differs from S4: -1712 "AppleEvent timed out" on macOS 27.0, from a script run on the main thread. Whether the background thread or the macOS update causes the difference is unknown.
  - The 130 s watchdog did not fire; the system's error came first.
- **Final.** Reset, then Allow: the Dock hid and came back (human), and the permission was left granted.

### C5 2026-10-20 macOS 27.0.1 (B5, menu bar)
- **Desktop, two `run`s with an 8 s hold.**
  - Machine: `menuBar` restored, diff empty.
  - Human: "the menu bar did not change", both times.
- **Diagnostic.**
  - Machine: `activate` left the session active; `defaults` showed the "Always" row (0, true, false).
  - Human (screenshot): the menu bar was **hidden** on the desktop.
  - `recover` (machine: restored, diff empty); human: the menu bar came back.
  - Verdict: in-app `CFPreferences` read and write of the three keys, and the notification posted from the real app, both work. The two "no change" reports were not reproduced.
- **Full screen** (human, screenshot): the menu bar stayed hidden in full screen and appeared at the top edge, as with the user's own setting. No change was expected or seen.
- The store gained one entry for the full-screen Space: macOS does this, not the tool.

### C6 2026-10-20 macOS 27.0.1 (B6, hide apps)
- **Defect, found and fixed.**
  - Machine: `NSRunningApplication.hide()` returned **false** for TextEdit while TextEdit **did hide** (human; `world` showed `isHidden` true).
  - The action recorded it as refused, so the restore never unhid it. The user unhid it by hand, and the diff was then empty.
  - In another run `hide()` returned false and Calculator did not hide.
  - Fix (`fix(platform)`, commit 123c86a): `AppKitWorkspaceAdapter` ignores the returned `Bool`, watches `isHidden` of every instance for up to 2 s (polled every 50 ms), and reports `changed` only when every instance reached the wanted state. The commit message calls this check C4; it is C6 here.
- **After the fix.**
  - Machine: `hide` and `unhide` both reported `changed` for TextEdit and Calculator; `hideApps` restored; diff empty.
  - Human: both apps hid and came back.
- **Frontmost** (machine): the tool's frontmost application equals `lsappinfo front`. Focus stays on the last app clicked; switching Spaces alone can leave a full-screen app frontmost, and the frontmost app is never hidden.
- **Several instances** (machine): with a second TextEdit instance (`open -n`), mid-hold `world` showed both instances hidden; afterwards both were visible. One request per bundle identifier covers every instance.
- **User unhides one** (machine): no `unhide` was sent to TextEdit, Calculator was unhidden, outcome `restored`.
- **User unhides both** (machine): no `unhide` was sent, outcome `skippedBecauseChangedByUser`.
- **User quits Calculator** (machine): it was not relaunched, TextEdit was unhidden, outcome `restored`.
- **Full screen.**
  - Machine: `hide` and `unhide` of a full-screen TextEdit both reported `changed`.
  - Human: in Mission Control the full-screen Space thumbnail did **not** change during a 30 s hold.
  - Probe at +2, +10 and +20 s, machine: `NSRunningApplication.isHidden` true, `lsappinfo` `Hidden` true, and the window server still listed the same 7 TextEdit windows, none on screen (as before and after).
  - Conclusion: the hidden state of a full-screen app is set and restored, but its full-screen Space keeps its window. There is no visible benefit, the effect is harmless, and switching to that Space activates and unhides the app.
- The System Events `visible of process` probe was not used: it would need an Automation permission for the Claude app.

### C7 2026-10-20 macOS 27.0.1 (B7, wallpaper)
- **Structure before** (machine): a custom color in a `linked` entry; 55 Space entries plus `""`.
- **Solid color, 20 s hold.**
  - Machine: activation 0.25 s including the poll; `killall WallpaperAgent` exited 0; `wallpaper` restored; the independent store comparison is equal, ignoring `LastUse`.
  - Human: blue on the current Space only, the other Space unchanged, the original back.
  - Verdict: `setDesktopImage` through the adapter changes the current Space only. The atomic replace of `Index.plist` followed by `killall WallpaperAgent` restores exactly.
- **Post-apply structure** (machine, shapes only): the display entry and the all-Spaces entry changed from `Linked` to `Desktop` plus `Idle` (`individual`). `Configuration` became an image configuration with `url.relative`; `EncodedOptionValues` holds `color` and `placement`.
- **Latency, 12 runs** (machine): `setDesktopImage` returned in 3–6 ms; the store changed after a median of 154 ms (p95 160 ms). After the fingerprint fix below: median 153 ms, p95 161 ms. The ADR-038 rule gives `max(50, ceil(4 × 161 / 100)) = 50` polls, so the constants are unchanged.
- **Defect, found and fixed.**
  - Machine: an image run reported `wallpaper` as **skipped, changed by the user**, although nobody touched it, and the image stayed (human). The emergency restore script put the store back; diff empty.
  - Traces of every store version showed the apply writing only `Spaces[""]` once, at about 200 ms. After a `WallpaperAgent` restart, the agent rewrote `Displays[<display>]` and `SystemDefault` by itself, and `Displays` was part of the fingerprint.
  - Fix (`fix(platform)`, commit 7650dad): the fingerprint covers `Spaces[""]` only.
  - After the fix, the same sequence (a latency round restarting the agent, then the image run) restored correctly; human: the original came back.
  - During the traces an `activate` session was left un-recovered by the operator, which caused one more skipped restore; the emergency restore fixed it. That was a protocol slip, not a product defect.
- **Interrupted apply, twice** (machine): the store had not changed before the restore; it equaled the baseline right after the restore and 10 s later. Human: a short flash, then the original. Verdict: the `WallpaperAgent` restart discards a change that was not yet saved, and no late write overwrote the restore.
- Second display: untested (one display).

### C8 2026-10-20 macOS 27.0.1 (B8, whole session and crash)
- **All five steps, 15 s hold.**
  - Machine: activation 0.65 s; report restored `wallpaper`, `hideApps`, `menuBar`, `dock`, `desktopIcons`; diff empty.
  - Human: all five effects seen, and all came back.
- **Crash.**
  - Machine: `activate` with the same steps, then `kill -9` of the app process. `session.json` remained and the keys stayed at the target.
  - `recover` in a new process restored all five, removed `session.json`, and the diff is empty.
  - Human: the effects stayed after the kill and all came back on recover.

### C9 2026-10-20 macOS 27.0.1 (B9, the user's changes during a session)
- Machine: a 90 s session with all five steps. The user turned Dock auto-hide off and chose another wallpaper in System Settings during the hold.
- The deactivate reported `dock` and `wallpaper` **skipped, changed by the user**, and restored `hideApps`, `menuBar` and `desktopIcons`. The user's Dock value and wallpaper were kept, and there was no agent restart.
- Human: their choices were kept and the rest came back.
- Verdict: the `Spaces[""]` fingerprint detects a real wallpaper change made in System Settings.

### C10 2026-10-20 macOS 27.0.1 (B10, final)
- Machine: `adapter-check-restore.sh` with the first backup wrote Dock auto-hide back on and restarted the Dock, copied `Index.plist` back, restarted `WallpaperAgent`, and posted the menu bar notification.
- TextEdit and Calculator were quit; they were opened for the protocol.
- Final `adapter-check-diff.sh` against the first backup: keys, applications and displays equal; the store equal except one Space entry present now and absent this morning. A second copy and agent restart added it again, so the agent creates it for a currently existing Space. It changes no wallpaper.
- Human: the original wallpaper, Dock, icons and menu bar are back, and the number of Spaces is the same.
