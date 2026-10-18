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

Schema migration: each file carries `schemaVersion`. Unknown future version = refuse to overwrite, show an error, keep the file. An unreadable profiles file is kept as `profiles.json.corrupt` before the next save; an unreadable session file is never overwritten and only `clearSession` removes it (ADR-030). Implemented by `ProfileStore` and `SessionStore` (actors whose file operations run one after another) over one shared policy type; the directory is injected by the composition root. Formats and full policy: `docs/12-data-formats.md`.

## Error policy

ModeKit uses Swift `throws` with typed error enums per component (`SessionError`, `ActionError`, `StoreError`). No mixed strategies inside a module. UI layer converts errors to localized, actionable messages. No error is swallowed; no `catch {}`.

## Dependency injection

Constructor injection. `AppEnvironment` in `Application/` builds the object graph once at launch and passes protocols down. No service locators, no static shared instances.

## System ports (protocols in ModeKit, implementations in Platform except `FileStore`)

| Port | Real implementation |
|---|---|
| `DefaultsStore` | `defaults` domain read, write and delete via `UserDefaults(suiteName:)` / `CFPreferences`. Delete is required: restore removes keys that were absent at capture (S1, S4, S5) |
| `ProcessRunner` | `Process` with argv arrays (never a shell string) |
| `AppleScriptRunner` | `NSAppleScript` / `OSAScript` |
| `WorkspaceAdapter` | `NSWorkspace`, `NSRunningApplication`, `NSScreen` |
| `Clock` | `ContinuousClock` wrapper for timer tests |
| `FileStore` | `FileManagerFileStore` in ModeKit (Foundation only, ADR-029): temporary file, `fsync`, `rename(2)`. Implemented in M1; the other ports arrive with the branch that first needs them |
| `DistributedNotifier` | `DistributedNotificationCenter` post; applies menu bar changes live (ADR-026) |

## Logging

`os.Logger`, subsystem = bundle identifier, one category per component (`session`, `actions`, `platform`, `ui`). No PII, no file paths of user documents at `.public` privacy. Every session transition logs one structured line with a session ID.

## Threading

Domain and platform adapters are `Sendable` and async. Main-actor work is limited to view models and AppKit calls that require it. No `DispatchQueue.main.async` in new code; use `@MainActor`.
