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

```swift
public struct Profile: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var steps: [ProfileStep]        // ordered, each step typed
    public var autoExit: Duration?         // nil = off
}

public enum ProfileStep: Codable, Sendable {
    case hideDesktopIcons
    case hideDock
    case hideMenuBar
    case hideApps(exclusions: Set<BundleIdentifier>)
    case wallpaper(WallpaperChoice, displays: DisplaySelection)
}
```

Exact shapes are decided in the M1 task and must stay within these ideas: typed steps, no stringly-typed dictionaries, `Codable` with an explicit schema version.

## Action contract

```swift
public protocol ModeAction: Sendable {
    associatedtype Snapshot: Codable & Sendable
    var identifier: ActionIdentifier { get }
    func capture() async throws -> Snapshot
    func apply() async throws -> AppliedState      // what we set, for conditional restore
    func restore(_ snapshot: Snapshot, expecting: AppliedState) async throws
}
```

Heterogeneous snapshots are persisted through a `Codable` envelope: `ActionRecord { identifier, snapshotData, appliedData }`. Type erasure (`AnyModeAction`) is internal to ModeKit.

Rules:

- `capture` reads only. No side effects.
- `apply` is idempotent-safe: applying twice does not corrupt the snapshot.
- `restore` is conditional (ADR-008): if the current system value no longer equals the value this app applied, the user changed it meanwhile; do not overwrite, log, and report `skippedBecauseChangedByUser`.
- Every action isolates its own failure. One action failing never prevents others from restoring.

## Session controller

An `actor SessionController` owns the state machine:

```
idle --activate--> applying --ok--> active --deactivate/timer--> restoring --ok--> idle
                       |                                              |
                    failure                                        failure
                       v                                              v
                  rollingBack --> idle                      degraded (retry available)
```

Order on activate: `capture all` -> `write session.json (atomic)` -> `apply each in profile order`.
Order on deactivate: `restore each in reverse order` -> `delete session.json` only if all restores succeeded or were deliberately skipped. Otherwise keep the failed records and enter `degraded`.

Recovery: at launch, `SessionController.recoverIfNeeded()` runs before UI is shown. One automatic attempt. After that the user decides (menu item "Retry restore").

Concurrency: the controller serializes all transitions. A second trigger during `applying` or `restoring` is ignored and logged, never queued.

## Persistence

| Data | Location | Format |
|---|---|---|
| Profiles | `~/Library/Application Support/<BundleID>/profiles.json` | JSON, `schemaVersion` field, atomic writes |
| Active session | `~/Library/Application Support/<BundleID>/session.json` | JSON, atomic write, `fsync` before apply |
| Preferences (appearance, language, launch at login, hotkey) | `UserDefaults` | typed wrapper, one key enum |
| Generated solid-color wallpapers | `~/Library/Application Support/<BundleID>/wallpapers/` | PNG |

Schema migration: each file carries `schemaVersion`. Unknown future version = refuse to overwrite, show an error, keep the file.

## Error policy

ModeKit uses Swift `throws` with typed error enums per component (`SessionError`, `ActionError`, `StoreError`). No mixed strategies inside a module. UI layer converts errors to localized, actionable messages. No error is swallowed; no `catch {}`.

## Dependency injection

Constructor injection. `AppEnvironment` in `Application/` builds the object graph once at launch and passes protocols down. No service locators, no static shared instances.

## System ports (protocols in ModeKit, implementations in Platform)

| Port | Real implementation |
|---|---|
| `DefaultsStore` | `defaults` domain read/write via `UserDefaults(suiteName:)` / `CFPreferences` |
| `ProcessRunner` | `Process` with argv arrays (never a shell string) |
| `AppleScriptRunner` | `NSAppleScript` / `OSAScript` |
| `WorkspaceAdapter` | `NSWorkspace`, `NSRunningApplication`, `NSScreen` |
| `Clock` | `ContinuousClock` wrapper for timer tests |
| `FileStore` | `FileManager` with atomic writes |

## Logging

`os.Logger`, subsystem = bundle identifier, one category per component (`session`, `actions`, `platform`, `ui`). No PII, no file paths of user documents at `.public` privacy. Every session transition logs one structured line with a session ID.

## Threading

Domain and platform adapters are `Sendable` and async. Main-actor work is limited to view models and AppKit calls that require it. No `DispatchQueue.main.async` in new code; use `@MainActor`.
