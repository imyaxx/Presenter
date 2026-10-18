# Architecture

## Principles

- Domain logic is separated from the operating system. All system calls sit behind protocols and are replaced by fakes in tests.
- The user's system state is sacred. Capture, persist, apply. Restore never depends on in-memory state alone.
- Unidirectional dependencies. UI depends on domain; domain depends on nothing.
- Small types with one job. Explicit dependencies. No singletons.

## Layers

```
App target (PresenterApp)
  Features/*  (SwiftUI views + @Observable view models)
        |  depends on
  Platform/*  (adapters: implement ModeKit protocols with real macOS APIs)
        |  depends on
  ModeKit     (Swift Package: models, actions, session controller, persistence, protocols)
  DesignSystem (tokens, theme, components; no knowledge of features or ModeKit)
```

Allowed imports:

| Module | May import |
|---|---|
| `ModeKit` | Foundation only |
| `DesignSystem` | SwiftUI, AppKit |
| `Platform` | `ModeKit`, AppKit, ServiceManagement, third-party hotkey package |
| `Features` | `ModeKit`, `DesignSystem`, SwiftUI. Never `Platform` directly; receives protocols |
| `Application` (composition root) | Everything. The only place where concrete types are wired |

## ModeKit domain model

Implemented in `Packages/ModeKit/Sources/ModeKit/Model/` (M1, branch `feat/modekit-models-and-persistence`). All types are public value types, `Codable`, `Hashable` and `Sendable`:

```swift
public struct Profile {
    public let id: UUID
    public let name: String                // 1...60 characters after trimming, stored trimmed
    public let steps: [ProfileStep]        // array order is the apply order; each kind at most once
    public let autoExit: AutoExit?         // nil = off
}

public enum ProfileStep {
    case hideDesktopIcons
    case hideDock
    case hideMenuBar
    case hideApps(exclusions: Set<BundleIdentifier>)
    case wallpaper(WallpaperChoice, displays: DisplaySelection)
    var actionIdentifier: ActionIdentifier
}

public enum WallpaperChoice { case solidColor(SolidColor), image(URL) }        // file URL, stored as a path
public struct SolidColor { red, green, blue: UInt8 }                           // 8-bit sRGB
public enum DisplaySelection { case allDisplays, specific(Set<DisplayIdentifier>) }   // specific: non-empty
public struct DisplayIdentifier { uuid: UUID }
public struct BundleIdentifier { rawValue: String }   // strict reverse DNS, validated on init and decode
public struct AutoExit { seconds: Int; duration: Duration }   // 60...86 400 whole seconds
public enum ActionIdentifier: String { desktopIcons, dock, menuBar, hideApps, wallpaper }
```

`ProfileValidation` holds every rule and throws `ProfileValidationError`. `BundleIdentifier` and `AutoExit` cannot hold an invalid value. The JSON format and the rules are in `docs/12-data-formats.md`. Focus is not a step yet; it arrives with its action if ADR-013 is confirmed.

## Action contract

Implemented in `Packages/ModeKit/Sources/ModeKit/Session/` (ADR-032). The contract is split so that crash recovery restores from a persisted record without the profile, which may have been edited or deleted since:

```swift
public enum RestoreOutcome { case restored, skippedBecauseChangedByUser }

public protocol ActionRestorer: Sendable {
    associatedtype Snapshot: Codable & Sendable
    associatedtype AppliedState: Codable & Sendable
    var identifier: ActionIdentifier { get }
    func restore(_ snapshot: Snapshot, expecting applied: AppliedState?) async throws -> RestoreOutcome
}

public protocol ModeAction: ActionRestorer {
    func capture() async throws -> Snapshot
    func apply() async throws -> AppliedState      // what we set, for conditional restore
}

public protocol ActionFactory: Sendable {          // implemented by the composition root
    func makeAction(for step: ProfileStep) throws -> any ModeAction
    func makeRestorer(for identifier: ActionIdentifier) throws -> any ActionRestorer
}
```

`applied` is nil when the apply was interrupted (crash, or a failure while applying this action): the system may be partly changed and the applied value is unknown, so the restore is unconditional.

Heterogeneous snapshots are persisted through a `Codable` envelope: `ActionRecord { identifier, snapshotData, appliedData }`. Type erasure (`AnyModeAction`, `AnyActionRestorer`) is internal to ModeKit and encodes `Snapshot` and `AppliedState` to `Data` with the persistence coder. A record that cannot be decoded fails with `ActionError.undecodableRecord`; an identifier with no registered action or restorer fails with `ActionError.unsupported`.

Rules:

- `capture` reads only. No side effects.
- `apply` is idempotent-safe: applying twice does not corrupt the snapshot.
- `restore` is conditional (ADR-008): if the current system value no longer equals the value this app applied, the user changed it meanwhile; do not overwrite, log, and report `skippedBecauseChangedByUser`.
- Every action isolates its own failure. One action failing never prevents others from restoring.

## Action mechanisms (verified in M0)

Each action's mechanism, ports and snapshot shape, from the spikes in `docs/07-macos-integration.md`:

| Action | Ports | Snapshot | Decision |
|---|---|---|---|
| Desktop icons | `DefaultsStore`, `ProcessRunner` (`killall Finder`) | `CreateDesktop` value or absent | ADR-028 |
| Dock | `AppleScriptRunner` (System Events), `DefaultsStore` (delete when absent) | `autohide` value or absent | ADR-025 |
| Menu bar | `DefaultsStore`, `DistributedNotifier` | the three keys, each value or absent | ADR-026 |
| Wallpaper | `WorkspaceAdapter` (apply), `FileStore` (store bytes), `ProcessRunner` (`killall WallpaperAgent`) | bytes of the wallpaper store `Index.plist`; apply covers the current Space only | ADR-027 |
| Focus (if ADR-013 is confirmed) | `ProcessRunner` (`shortcuts run`) with a timeout | active Focus name from the user's "Get Current Focus" Shortcut, or none | ADR-013 |

## Session controller

An `actor SessionController` owns the state machine:

| From | Event | To |
|---|---|---|
| `idle` (after recovery) | `activate` | `applying` |
| `applying` | every action applied | `active` |
| `applying` | capture failed, or writing `session.json` before the first apply failed | `idle` |
| `applying` | apply of a step failed | `rollingBack` |
| `rollingBack` | every rollback restore restored or skipped | `idle` |
| `rollingBack` | a rollback restore failed | `degraded(.restoreFailed)` |
| `active` | `deactivate` or auto-exit timer | `restoring` |
| `restoring` | every restore restored or skipped | `idle` |
| `restoring` | a restore failed | `degraded(.restoreFailed)` |
| `idle` (at launch) | `recoverIfNeeded`: no file | `idle` |
| `idle` (at launch) | `recoverIfNeeded`: unreadable or newer file | `degraded(.unreadableSessionFile)` |
| `idle` (at launch) | `recoverIfNeeded`: readable file | `restoring` |
| `degraded` | `retryRestore`: readable file | `restoring` |
| `degraded` | `retryRestore`: no file | `idle` |
| `degraded` | `retryRestore`: unreadable file | `degraded(.unreadableSessionFile)` |
| `degraded(.unreadableSessionFile)` | `discardUnreadableSession` | `idle` |

Public API: `state`, `stateUpdates()` (current state first, then every change), `recoverIfNeeded()`, `activate(_:)`, `deactivate()`, `retryRestore()`, `discardUnreadableSession()`. Triggers return `TriggerResult.performed(value)` or `.ignored(currentState:)`.

Activate (only from `idle`, only after recovery has run, otherwise `SessionError.recoveryNotRun`): validate the profile -> build every action through the factory -> `applying` -> capture all in profile order -> write `session.json` with no applied state (atomic, before the first apply) -> apply each in profile order, writing `session.json` again with each action's applied state right after its apply -> `active`, and start the auto-exit timer when the profile has one.

Apply failure at step N (the action throws, or writing its applied record fails): `rollingBack`; restore step N with `applied: nil` (or its in-memory applied state when only the write failed) and the earlier steps in reverse, conditionally. All restored or skipped: remove `session.json`, `idle`. A rollback restore failed: rewrite `session.json` with only the failed records, `degraded(.restoreFailed)`. Either way activation throws `SessionError.applyFailed(failure, rollback: report)`.

Deactivate (only from `active`) and the auto-exit timer: `restoring`; restore every record in reverse; one failing never stops the others. All restored or skipped: remove `session.json`, `idle`. Some failed: keep only the failed records in `session.json`, `degraded(.restoreFailed)`; the failures are in the returned `RestoreReport`, not thrown. Removing the file after a complete restore can fail: the state is still `idle` and deactivate throws `sessionStoreFailed`; the stale file is harmless because the next activation overwrites it and a recovery restores conditionally.

Timer: a task that sleeps on `SessionClock` and runs the deactivate path. Every deactivate, rollback and recovery cancels it; a timer that fires after its session ended does nothing.

Recovery: at launch, `recoverIfNeeded()` runs once, before UI and before any activation; later calls return `alreadyAttempted`. It restores from `session.json` and `makeRestorer(for:)` only, never the profile, with the same rules as deactivate, and starts no timer. A corrupted or newer `session.json` is not touched: `degraded(.unreadableSessionFile)`, outcome `blocked`. A record that cannot be decoded or has no restorer is a restore failure for that action and stays in the file.

Degraded: `retryRestore()` reloads `session.json` and runs the same restore pass (an unreadable file may have become readable). `discardUnreadableSession()` is the user's explicit decision to abandon an unreadable file: it removes it and returns to `idle`.

Concurrency: an actor. Every trigger reads the state and, when accepted, sets the next state before its first suspension; retry and discard additionally hold a flag while they run. A trigger the state does not accept is ignored and logged, never queued. Switching profiles while active is not a v1 flow. There is no controller-level timeout: a hung action holds the controller in `applying` or `restoring`; timeouts belong to the adapters (docs/03-code-standards.md, ADR-032).

## Persistence

| Data | Location | Format |
|---|---|---|
| Profiles | `~/Library/Application Support/<BundleID>/profiles.json` | JSON, `schemaVersion` field, atomic writes |
| Active session | `~/Library/Application Support/<BundleID>/session.json` | JSON, atomic write, `fsync` before apply |
| Preferences (appearance, language, launch at login, hotkey) | `UserDefaults` | typed wrapper, one key enum |
| Generated solid-color wallpapers | `~/Library/Application Support/<BundleID>/wallpapers/` | PNG |

Schema migration: each file carries `schemaVersion`. Unknown future version = refuse to overwrite, show an error, keep the file. An unreadable profiles file is kept as `profiles.json.corrupt` before the next save; an unreadable session file is never overwritten and only `clearSession` removes it (ADR-030). Implemented by `ProfileStore` and `SessionStore` (actors whose file operations run one after another) over one shared policy type; the directory is injected by the composition root. Formats and full policy: `docs/12-data-formats.md`.

## Error policy

ModeKit uses Swift `throws` with typed error enums per component: `SessionError` (`invalidProfile`, `recoveryNotRun`, `captureFailed`, `sessionStoreFailed`, `applyFailed(failure, rollback:)`), `ActionError` (`unsupported`, `undecodableRecord`), `StoreError`, `ProfileValidationError`. Per-action restore failures are reported in `RestoreReport` as `ActionFailure { identifier, reason }`, not thrown; `reason` is a non-localized diagnostic and the UI maps by identifier and phase. No mixed strategies inside a module. UI layer converts errors to localized, actionable messages. No error is swallowed; no `catch {}`.

## Dependency injection

Constructor injection. `AppEnvironment` in `Application/` builds the object graph once at launch and passes protocols down. No service locators, no static shared instances.

## System ports (protocols in ModeKit, implementations in Platform except `FileStore` and `SessionClock`)

| Port | Real implementation |
|---|---|
| `DefaultsStore` | `defaults` domain read, write and delete via `UserDefaults(suiteName:)` / `CFPreferences`. Delete is required: restore removes keys that were absent at capture (S1, S4, S5) |
| `ProcessRunner` | `Process` with argv arrays (never a shell string) |
| `AppleScriptRunner` | `NSAppleScript` / `OSAScript` |
| `WorkspaceAdapter` | `NSWorkspace`, `NSRunningApplication`, `NSScreen` |
| `SessionClock` | `SystemSessionClock` in ModeKit: `Date()` and `ContinuousClock` sleep. Not named `Clock`, which would shadow the standard library protocol (ADR-032) |
| `SessionLogger` | `os.Logger` adapter with privacy annotations, in Platform (M2). Receives typed `SessionEvent`s; `reason` strings may contain paths and are logged as private. ModeKit never imports `os` |
| `FileStore` | `FileManagerFileStore` in ModeKit (Foundation only, ADR-029): temporary file, `F_FULLFSYNC`, `rename(2)`, directory flush (ADR-033). Implemented in M1; the other ports arrive with the branch that first needs them |
| `DistributedNotifier` | `DistributedNotificationCenter` post; applies menu bar changes live (ADR-026) |

## Logging

`os.Logger`, subsystem = bundle identifier, one category per component (`session`, `actions`, `platform`, `ui`). No PII, no file paths of user documents at `.public` privacy. ModeKit logs through the `SessionLogger` port: one `SessionEvent` per state transition and per action step, with the session ID.

## Threading

Domain and platform adapters are `Sendable` and async. Main-actor work is limited to view models and AppKit calls that require it. No `DispatchQueue.main.async` in new code; use `@MainActor`.
