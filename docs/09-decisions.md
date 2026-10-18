# Decision log

Format: ID, decision, rationale, consequences, status. Append new ADRs; never rewrite history. A reversal is a new ADR that supersedes the old one.

## Accepted

**ADR-001 Minimum macOS 14 (Sonoma).** Reach of live Macs and access to `@Observable`, modern SwiftUI. Consequence: no macOS 13 workarounds.

**ADR-002 Swift 6 with SwiftUI plus AppKit.** SwiftUI for views and `MenuBarExtra`; AppKit for the HUD panel, appearance application, and anything SwiftUI cannot do cleanly.

**ADR-003 MVVM on `@Observable`, services behind protocols.** Simple, no external architecture framework, testable by substituting services. TCA rejected: heavy dependency, high contributor barrier.

**ADR-004 Domain in a local Swift package (`ModeKit`), Foundation only.** Enforces the boundary mechanically, allows fast `swift test`, keeps logic independent of AppKit.

**ADR-005 XcodeGen (`project.yml`).** The `.xcodeproj` is generated and not committed: readable diffs, no merge conflicts, friendly to automated editing.

**ADR-006 No App Sandbox; direct distribution only.** The app writes Finder and Dock preferences, spawns processes, and sends Apple Events. Not eligible for the Mac App Store.

**ADR-007 Snapshot, persist, then apply.** The session file is written atomically before any system change. Restore works after crash or reboot.

**ADR-008 Conditional restore.** Restore writes the captured value only if the current system value still equals what this app applied. If the user changed it meanwhile, leave it and report. Prevents clobbering deliberate user changes. Proposed by the assistant; user to confirm or reverse.

**ADR-009 Unhide only apps this app hid.** Apps already hidden before activation stay hidden after deactivation. Chosen by the user.

**ADR-010 Finder restart for desktop icons is acceptable.** Chosen by the user.

**ADR-011 Wallpaper is per display; menu bar, Dock, and desktop icons are global.** Menu bar and Dock auto-hide are system-wide settings; per-display behavior is `UNVERIFIED` and not planned. Correction to an earlier discussion message that mentioned per-display menu bar configuration.

**ADR-012 Hotkey has no default; the user records it in onboarding.** Avoids collisions. Library: `KeyboardShortcuts`, subject to a maintenance check.

**ADR-014 Distribution: GitHub Releases and Homebrew cask, no auto-update in v1.** No dependency on paid signing for the first release. Chosen by the user.

**ADR-015 License MIT.** Chosen by the user.

**ADR-016 Interface languages: English (source) and Russian, via String Catalog.** Chosen by the user.

**ADR-017 Git: trunk-based, short branches, Conventional Commits, squash-merge, protected `main`.** See `docs/05-git-workflow.md`.

**ADR-018 Tooling: XcodeGen, SwiftLint (strict), swift-format, checked in CI.** Chosen by the user.

**ADR-019 Appearance preference: System (default), Light, Dark; settings control overrides OS.** Applied via `NSApp.appearance`. Chosen by the user.

**ADR-021 No network access, no telemetry.** Privacy by construction.

**ADR-024 `ModeKit` manifest uses `swift-tools-version: 6.0`.** 6.0 is the lowest tools version with the Swift 6 language mode, which is all the manifest needs. Pinning it to the local toolchain (Swift 6.4, Xcode 27.1 on 2026-10-17) would break CI: the newest GitHub-hosted image `macos-26` ships Xcode 26.6 as its newest version (runner-images readme, checked 2026-10-17). Consequence: raise the tools version only when a manifest feature requires it and CI provides it. Decided by the assistant during bootstrap; user to confirm or reverse.

**ADR-023 Menu bar action stays in v1 (closes the open item of the same number).** Context: S1 (2026-10-17, macOS 27.0) found a live mechanism with no permission prompt (ADR-026). Decision: keep "Hide menu bar" in v1.0. Consequence: the mechanism depends on an undocumented distributed notification name; if a macOS release breaks it, the action reports a failure and is reconsidered. Proposed by the assistant from S1 evidence; user to confirm.

**ADR-025 Dock auto-hide through System Events, with `defaults delete` for an absent key.** Context: S4 compared System Events (`set autohide of dock preferences`) with `defaults write` plus `killall Dock`. System Events applies immediately with the normal animation and no Dock reload. `defaults` plus `killall` reloads the Dock visibly but needs no permission. Neither can restore an absent `autohide` key by writing a value. Decision: apply and restore with System Events. When the captured key was absent, restore writes `false` through System Events and then runs `defaults delete com.apple.dock autohide`; S4 showed no Dock restart is needed. The app ships `NSAppleEventsUsageDescription` and the `com.apple.security.automation.apple-events` entitlement, both added in the milestone that implements the action. S4 showed that without either one the call fails at once with -1743 and no prompt. Consequence: one Automation prompt for System Events, requested in onboarding through a real action. Denial (-1743) and an unanswered prompt (-1712 after 120 s) are errors the action reports. There is no silent fallback to `killall Dock`. Proposed by the assistant; user to confirm.

**ADR-026 Menu bar auto-hide through three preference keys plus a distributed notification.** Context: S1 found that the setting is `com.apple.controlcenter AutoHideMenuBarOption` (0 Always, 1 On Desktop Only, 2 In Full Screen Only, 3 Never) together with `NSGlobalDomain _HIHideMenuBar` and `NSGlobalDomain AppleMenuBarVisibleInFullscreen`. Writing them applies live only after posting `AppleInterfaceMenuBarHidingChangedNotification`. Decision: apply writes the "Always" row of all three keys and posts the notification. Restore writes each captured value, or deletes each key that was absent, then posts the notification. All three keys are always written, so System Settings shows the true state. Consequence: no permission is needed; the notification name is undocumented (see ADR-023). Proposed by the assistant; user to confirm.

**ADR-027 Wallpaper: apply through NSWorkspace, capture and restore through the wallpaper store.** Context: S2 showed that `setDesktopImageURL` changes only the current Space, and that `desktopImageURL` and `desktopImageOptions` misreport color and dynamic wallpapers (they return `DefaultDesktop.heic`). Copying a captured `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` back and running `killall WallpaperAgent` restored a color and a dynamic wallpaper exactly. Decision: the snapshot is the store file's bytes, captured atomically into the session record. Apply uses `setDesktopImageURL` with a generated solid-color PNG or the user's image, per selected display, on the current Space. Restore writes the captured store back and restarts `WallpaperAgent`, conditional on the current Space's entry still being the one this app applied (ADR-008). Consequence: "neutral wallpaper" covers the current Space of each display only. The store and the agent restart are undocumented. A whole-file restore also drops Space entries created during the session. A `WallpaperAgent` restart regenerates Aerial thumbnails (cache). Multi-display behavior is untested until a second display is available. Proposed by the assistant; user to confirm.

**ADR-028 Desktop icons: `killall Finder` and delete-on-absent restore.** Context: S5 showed that `defaults write com.apple.finder CreateDesktop -bool false` plus `killall Finder` hides the icons within about 0.1 s, launchd relaunches Finder, open windows reopen, and the key is absent by default. Decision: apply writes `false` and runs `killall Finder`. Restore deletes the key when it was absent at capture, otherwise writes the captured value, then runs `killall Finder`. Consequence: the restart side effects accepted in ADR-010 apply on both apply and restore. Window survival beyond two plain windows is untested. Proposed by the assistant; user to confirm.

**ADR-029 The real `FileStore` lives in ModeKit (Foundation only), not in Platform.** Context: `docs/01-architecture.md` puts every real port implementation in the app's `Platform/` folder. The file store needs only Foundation, and the stores and their integration tests run with `swift test` without the app. Decision: `FileManagerFileStore` (temporary file, `fsync`, `rename(2)`) is public in ModeKit; `FileStore` stays a port so tests use `InMemoryFileStore`. Consequence: `Platform/` holds only adapters that need AppKit or other non-Foundation frameworks. The composition root still decides which store to use and passes the directory. Proposed by the assistant; user to confirm.

**ADR-030 On-disk format and file policy.** Context: `profiles.json` is user data that power users edit by hand; `session.json` is the record that makes restore possible after a crash (ADR-007). Decision: (1) every enumeration with fields is coded with an explicit `type` discriminator, never the synthesized format, and unknown types fail decoding; (2) `schemaVersion` 1 stays mutable until the first release, after which every shape change raises the version and adds a migration in the same change; (3) a file with a newer `schemaVersion` is refused on read and write and never modified; (4) before a save overwrites an unreadable profiles file, the file is kept byte for byte as `profiles.json.corrupt`; (5) an unreadable session file is never overwritten, only `clearSession` removes it, because it may describe system changes that were never reverted. Consequence: hand edits can be lost only after a copy is kept; a corrupt session file blocks new sessions until the caller resolves it explicitly. Details in `docs/12-data-formats.md`. Proposed by the assistant; user to confirm.

**ADR-031 Apply order is the profile's step order; restore is the reverse.** Context: `docs/00-product-brief.md` said "a fixed order", `docs/01-architecture.md` said "profile order", and the data layer stores the step array order. Decision: actions apply in the profile's step order and restore in reverse; the brief now says so. Consequence: the user controls the order through the profile; actions must not assume a fixed position. Proposed by the assistant; user to confirm.

**ADR-032 Split action contract, `applied: nil` restores, `SessionClock` and `SessionLogger` ports, no controller watchdog.** Context: recovery after a crash must work when the profile was edited or deleted, and an apply can be interrupted half-way. Decision: `ActionRestorer` (identifier and `restore(_:expecting:)`) is separate from `ModeAction` (adds `capture` and `apply`), and `ActionFactory.makeRestorer(for:)` builds restorers from an identifier alone. `applied` is nil when the apply was interrupted; the restore is then unconditional. The ports are named `SessionClock` (not `Clock`, which would shadow the standard library protocol) and `SessionLogger` with a typed `SessionEvent`, so ModeKit never imports `os`. The controller has no watchdog; timeouts belong to the adapters. Consequence: after a crash, an interrupted action is restored to its snapshot even if the user changed the value in the meantime, because leaving the system half-applied is worse. A hung action holds the controller in `applying` or `restoring` until its adapter times out. Proposed by the assistant; user to confirm.

**ADR-033 Durable file writes.** Context: `session.json` is the only way to undo system changes after a crash or power loss (ADR-007), and per fsync(2) plain `fsync` does not force data out of the drive's buffers. Decision: `FileManagerFileStore` flushes the temporary file with `fcntl(F_FULLFSYNC)`, falling back to `fsync` only on `ENOTSUP` or `ENOTTY`, and after the `rename` flushes the parent directory the same way, best effort. Consequence: every write, including `profiles.json`, costs one full flush; measured median 3.8 ms on the M0 test Mac's SSD (20 runs), more on slower drives. Durability under real power loss is unverified. Proposed by the assistant; user to confirm.

## Open

**ADR-013 Focus / Do Not Disturb.** No public API. Only path is a user-installed Shortcut invoked with `shortcuts run`. Decision after spike S3: ship in v1.0, defer to v1.1, or drop. Update 2026-10-17 after S3, **proposed, user to confirm**: ship Focus in v1.0 as an optional action. Onboarding contains a manual setup guide: the user builds a "Set Focus: Do Not Disturb On" Shortcut, an "Off" Shortcut and, optionally, a "Get Current Focus" Shortcut for capture. The Shortcut names are configurable. The app runs them with `shortcuts run`. Reason: S3 measured on and off at 0.14 to 0.18 s and state reads at 0.11 to 0.15 s; a missing Shortcut fails fast with exit 1; reading the previous state works after a one-time "output 1 focus?" prompt, which blocks until answered and so needs a timeout. Distribution of a prebuilt `.shortcut` file is deferred until a dedicated project Apple Account exists (M5), because exporting for "Anyone" requires an iCloud sign-in. Proposed by the user in the M0 session.

**ADR-020 Product name and identifiers.** Codename `Presenter` is used in code until decided. Name and bundle ID prefix live in `project.yml` only. Before choosing: check GitHub, Homebrew, and trademark conflicts.

**ADR-022 Code signing and notarization.** Depends on audience; build and CI must work unsigned. Decide before M5.

**ADR-023 Menu bar action feasibility.** Decided after spike S1; if no live mechanism exists the action is removed from v1. Update 2026-10-17: closed by S1; see the accepted ADR-023 entry above.
