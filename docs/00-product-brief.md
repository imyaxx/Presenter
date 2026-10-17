# Product brief

## Problem

Before a video call, a screen share, or a screen recording, the user manually hides desktop icons, the Dock, personal apps (Messages, Mail), and silences notifications. The steps are scattered across System Settings, Finder, and Dock. A private notification or a cluttered desktop appears on the shared screen.

## Product

A menu-bar app. One global hotkey or one click on the menu-bar icon activates a **profile**. A second trigger restores the previous state exactly. Several named profiles, each with its own set of actions.

## Users

Anyone who shares a screen or records one: remote workers, teachers, streamers, developers recording demos. Mac users of any technical level, so the default path must need no config files. Power users get the same data as a JSON file on disk.

## Scope: MVP (v1.0)

Actions available inside a profile:

| Action | Behavior |
|---|---|
| Hide desktop icons | Global. Finder setting, Finder restarts. |
| Hide Dock | Auto-hide on, previous state restored. |
| Hide menu bar | Auto-hide on, previous state restored. |
| Hide apps | A user-defined list. `Cmd+H` equivalent. |
| Neutral wallpaper | Per display. Solid color or user-chosen image. |
| Auto-exit timer | Optional per profile, off by default. |

Triggers: menu-bar click, one global hotkey (no default; user records it during onboarding).

Feedback: menu-bar icon state change plus a short HUD (about one second, centered). System notifications are never used, because Focus would suppress them.

Settings: profile list and editor, apps exclusion list, appearance (System / Light / Dark), language, launch at login, hotkey.

Onboarding: hotkey, launch at login, permissions (Automation), optional Focus shortcut (see ADR-013).

## Out of scope for v1.0

- Notification suppression through any private API. Only a user-installed Shortcut path is considered (open decision ADR-013).
- Calendar or app-launch triggers (Zoom, Teams detection). Planned after v1.0.
- CLI.
- Auto-update (Sparkle).
- Mac App Store distribution (impossible, no sandbox).
- Per-display menu bar or Dock behavior.
- Windows, Linux, iOS.
- Any network access, analytics, or telemetry. The app makes no network calls.

## Core flows

### Activate
1. Trigger fires (hotkey or menu).
2. Controller captures a snapshot of every action in the profile.
3. Snapshot is written to disk (`session.json`).
4. Actions are applied in a fixed order.
5. Icon switches to the active state, HUD shows the profile name.
6. If any action fails during apply, already applied actions are rolled back in reverse order, the session file is removed, the user sees an error HUD with the failed action name.

### Deactivate
1. Trigger fires again, or the timer expires.
2. Each action restores from its snapshot (conditional restore, ADR-008).
3. Session file is deleted only after restore finishes.
4. Icon returns to idle, HUD confirms.

### Crash or reboot while active
On next launch, if `session.json` exists, the app restores before showing any UI. If restore partly fails, the menu shows a persistent warning with a "Retry restore" item.

### First launch
Empty profile list. Onboarding explains the idea in one screen, records the hotkey, asks about launch at login, requests Automation permission through a real action, and offers to create the first profile.

## Differentiation

Existing tools (TogglePresent, UnDistracted, CleanSpark) offer a single mode or are outdated or closed. This project: multiple named profiles, exact state restore that survives crashes, per-display wallpaper, open source (MIT), native and local-only.

Competitor facts are from web search on 2026-10-17 and not independently verified. Re-check before public launch.

## Success criteria for v1.0

- A user with no Terminal knowledge can set up a profile in under two minutes.
- Activate and deactivate leave the Mac in the original state in 100% of manual test runs, including forced quit and reboot while active.
- No unexpected permission prompts after onboarding.
