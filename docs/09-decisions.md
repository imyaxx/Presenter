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

## Open

**ADR-013 Focus / Do Not Disturb.** No public API. Only path is a user-installed Shortcut invoked with `shortcuts run`. Decision after spike S3: ship in v1.0, defer to v1.1, or drop.

**ADR-020 Product name and identifiers.** Codename `Presenter` is used in code until decided. Name and bundle ID prefix live in `project.yml` only. Before choosing: check GitHub, Homebrew, and trademark conflicts.

**ADR-022 Code signing and notarization.** Depends on audience; build and CI must work unsigned. Decide before M5.

**ADR-023 Menu bar action feasibility.** Decided after spike S1; if no live mechanism exists the action is removed from v1.
