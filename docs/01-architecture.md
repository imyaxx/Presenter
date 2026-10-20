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
| `Platform` | `ModeKit`, Foundation, AppKit, CoreGraphics, ImageIO, UniformTypeIdentifiers, CryptoKit, `os`, Darwin, ServiceManagement, the third-party hotkey package. One file per type under `App/Sources/Platform/<Mechanism>/`, named by mechanism; never imported by `Features` (ADR-040) |
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

Each action's mechanism, ports and snapshot shape, from the spikes in `docs/07-macos-integration.md`. "Implemented" means implemented in `Packages/ModeKit/Sources/ModeKit/Actions/` against the ports and tested with fakes; the real adapters arrive in M2.

| Action | Ports | Snapshot | Decision | State |
|---|---|---|---|---|
| Desktop icons | `DefaultsStore`, `ProcessRunner` (`killall Finder`, 10 s) | `CreateDesktop` value or absent | ADR-028, ADR-035 | Implemented (`DesktopIconsAction`) |
| Dock | `AppleScriptRunner` (System Events, 130 s), `DefaultsStore` (read back; delete when absent) | `autohide` value or absent | ADR-025, ADR-035 | Implemented (`DockAction`) |
| Menu bar | `DefaultsStore`, `DistributedNotifier` (`AppleInterfaceMenuBarHidingChangedNotification`, posted once per apply and restore that writes) | the three keys, each value or absent | ADR-026, ADR-037 | Implemented (`MenuBarAction`) |
| Hide apps (no M0 spike) | `WorkspaceAdapter` (list, hide, unhide) | candidates: visible regular applications except this one, the frontmost one and the exclusions; applied: those that accepted the hide | ADR-009, ADR-036 | Implemented (`HideAppsAction`, restore in `HideAppsRestorer`) |
| Wallpaper | `WorkspaceAdapter` (displays, `setDesktopImage` on the current Space), `SolidColorImageRenderer`, `FileStore` (store bytes, generated PNG), `SessionClock` (polling), `WallpaperStoreInspector` (fingerprint), `ProcessRunner` (`killall WallpaperAgent`, 10 s) | bytes of the wallpaper store `Index.plist`; applied: the displays changed and the store fingerprint. Apply fails closed: the store is read and fingerprinted before any change, and apply fails unless the fingerprint changes within the polling window. Restore compares fingerprints, never the image URL | ADR-027, ADR-038, ADR-039 | Implemented (`WallpaperAction`, restore in `WallpaperRestorer`) |
| Focus (if ADR-013 is confirmed) | `ProcessRunner` (`shortcuts run`) with a timeout | active Focus name from the user's "Get Current Focus" Shortcut, or none | ADR-013 | Not started |

`StandardActionFactory` is the `ActionFactory` the app uses. Its `init(ports: ActionPorts, wallpaperLocations: WallpaperLocations)` takes every port grouped in `ActionPorts` and the store and generated-image locations the composition root resolves (ADR-038). It builds actions and restorers for all five steps and identifiers; `ActionError.unsupported` stays in the contract for anything the enums might gain. For `.hideApps` and `.wallpaper` it returns `HideAppsRestorer` and `WallpaperRestorer` as restorers, which need nothing from the profile. The actions are value types holding their ports, with no shared mutable state. The hide apps mechanism was not spiked in M0 (docs/07).

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

## App shell (M2, ADR-043)

**Launch order** (`PresenterMain`):
1. A Debug build started with `--adapter-check` runs the check tool and never reaches the app (ADR-042).
2. A second launch of the app activates the first instance and ends, before anything is built (`NSRunningApplicationInstanceGuard`). Two instances would race on `session.json`.
3. `PresenterApp` starts. Its `AppDelegate` builds `AppEnvironment` and, in `applicationWillFinishLaunching`, starts it.

**What `AppEnvironment` builds:** from `PlatformComposition`, the `ProfileStore` and `SessionStore` over `FileManagerFileStore` in the support directory, `StandardActionFactory`, the `SessionController` with `SystemSessionClock` and `OSSessionLogger`, the `MenuBarViewModel` and the `QuitCoordinator`.

**Starting a session.** One owned task subscribes to `stateUpdates()` and runs `recoverIfNeeded()`. Until recovery finishes, the popover shows "Restoring" and offers no trigger; recovery never depends on a view appearing.

**When the graph cannot be built** (`PlatformCompositionError`): the menu says the app could not start, offers Quit, and never activates anything.

**As the host of the unit tests** (`LaunchMode`, detected by the test runner's `XCTestConfigurationFilePath`): the app builds no session graph and skips the single-instance guard, so no test can recover or restore the user's real session.

**Features boundary:** `Features/MenuBar` defines `SessionControlling` (the state stream and the triggers), `ProfileLoading` and `ProfilesFolderRevealing`. `SessionController`, `ProfileStore` and `NSWorkspaceProfilesFolderRevealer` conform through extensions in `Application/`. The view model never sees a concrete type, and the app tests use fakes.

**Quit:** Quit in the popover and Cmd+Q both reach `applicationShouldTerminate`, which returns `.terminateLater`. `QuitCoordinator` deactivates an active session and waits at most 15 s. A restore still running at the deadline, or a degraded result, still lets the app quit: `session.json` persists and the next launch recovers (ADR-008). Other states quit at once.

## System ports (protocols in ModeKit, implementations in Platform except `FileStore` and `SessionClock`)

Every port has a real implementation since M2 branch 1 (`feat/platform-adapters`); `App/Sources/Application/PlatformComposition.swift` is the only place that builds them (ADR-040). Their real system effects are verified by the next branch, `feat/adapter-check-tool`.

| Port | Real implementation |
|---|---|
| `DefaultsStore` | Defined in ModeKit (`value(for:)`, `set(_:for:)`, `remove(_:)` over `DefaultsKey` and `DefaultsValue`; nil means absent, not false). M2 adapter: `CFPreferences` for other apps' domains, `UNVERIFIED` for `com.apple.finder` and `com.apple.dock` (docs/07). No timeout: local preference access (ADR-034). Real: `CFPreferencesDefaultsStore` (`Platform/Defaults`). |
| `ProcessRunner` | Defined in ModeKit: `run(ProcessCommand)` with an executable URL, an argv array (never a shell string) and a timeout; a nonzero exit is a `ProcessResult`, not an error. M2 adapter: `Process`, enforces the timeout (ADR-034). Real: `FoundationProcessRunner` (`Platform/Process`): SIGTERM on timeout or cancellation, SIGKILL after 2 s, returns only after the child exited. |
| `AppleScriptRunner` | Defined in ModeKit: `run(AppleScript, timeout:)`; `AppleScript` is built from a `StaticString` only, so nothing can be interpolated. M2 adapter: `NSAppleScript`, enforces the timeout, maps -1743 and -1712 through `AppleScriptError(code:message:)` (ADR-034). Real: `NSAppleScriptRunner` (`Platform/AppleScript`): one dedicated background thread, scripts never overlap, the timeout is a watchdog. |
| `WorkspaceAdapter` | Defined in ModeKit (M1) with only what hide apps uses: `runningApplications()` (regular applications as `RunningApplication`; entries with an invalid bundle identifier are skipped), `hide(_:)` and `unhide(_:)` returning `ApplicationVisibilityChange` (`changed` means the request was accepted, not that the effect was observed: hiding is asynchronous in AppKit). For the wallpaper: `connectedDisplays()` (display UUIDs) and `setDesktopImage(_:on:)`, which changes the current Space of that display only and throws when the file is missing or the display is gone (ADR-038). M2 adapter: `NSWorkspace`, `NSRunningApplication`, `NSScreen`. In-process, no timeout by design; must not block (ADR-036). Real: `AppKitWorkspaceAdapter` with `DisplayIdentifierMapping` and `WorkspaceError` (`Platform/Workspace`). |
| `SessionClock` | `SystemSessionClock` in ModeKit: `Date()` and `ContinuousClock` sleep. Not named `Clock`, which would shadow the standard library protocol (ADR-032) |
| `SessionLogger` | `os.Logger` adapter with privacy annotations, in Platform (M2). Receives typed `SessionEvent`s; `reason` strings may contain paths and are logged as private. ModeKit never imports `os`. Real: `OSSessionLogger` with the pure `SessionLogMessage` (`Platform/Logging`). |
| `FileStore` | `FileManagerFileStore` in ModeKit (Foundation only, ADR-029): temporary file, `F_FULLFSYNC`, `rename(2)`, directory flush (ADR-033). Implemented in M1; the other ports arrive with the branch that first needs them. Also reads and writes the wallpaper store bytes and the generated PNG files (ADR-038) |
| `SolidColorImageRenderer` | Defined in ModeKit (M1): `pngData(for: SolidColor)`. ModeKit has no image framework; the M2 adapter renders the PNG. Real: `CoreGraphicsSolidColorImageRenderer` (`Platform/Rendering`): 64 x 64 sRGB PNG. |
| `WallpaperStoreInspector` | Defined in ModeKit (M1): `fingerprint(of:)` returns a `WallpaperStoreFingerprint`; equal if and only if the wallpaper configuration this app can change is equal, ignoring volatile fields such as `LastUse`; throws `WallpaperStoreError.unrecognizedFormat` otherwise. The knowledge of the undocumented `Index.plist` format lives only in the M2 adapter (ADR-039). Real: `PropertyListWallpaperStoreInspector` with `PropertyListValue` (`Platform/Wallpaper`, ADR-041). |
| `ActionPorts`, `WallpaperLocations` | Plain values in ModeKit (M1): `ActionPorts` groups every port above that actions use (`SessionClock` included, for the wallpaper polling); `WallpaperLocations { storeURL, generatedImagesDirectory }` is injected by the composition root, ModeKit never resolves home or bundle paths. Real locations: `SystemLocations` (`Platform/Locations`). |
| `DistributedNotifier` | Defined in ModeKit (M1): `post(DistributedNotificationName)`; cannot report whether anything reacted. M2 adapter: `DistributedNotificationCenter` post; applies menu bar changes live (ADR-026). In-process, no timeout by design; must not block (ADR-037). Real: `DistributedNotificationCenterNotifier` (`Platform/Notifications`). |

## Logging

`os.Logger`, subsystem = bundle identifier, one category per component (`session`, `actions`, `platform`, `ui`). No PII, no file paths of user documents at `.public` privacy. ModeKit logs through the `SessionLogger` port: one `SessionEvent` per state transition and per action step, with the session ID.

`OSSessionLogger` (category `session`) is the real `SessionLogger`. Its subsystem is the bundle identifier read from `Bundle.main` by the composition root, never a literal. The pure `SessionLogMessage` turns each event into a level and a text:
- `info` is for state changes and successful steps; `error` is for failures.
- The public part holds states, action identifiers, phases and session IDs.
- `reason` strings, store errors and profile names go only to a detail logged as `.private`.

## Threading

Domain and platform adapters are `Sendable` and async. Main-actor work is limited to view models and AppKit calls that require it. No `DispatchQueue.main.async` in new code; use `@MainActor`.

Rules for the M2 adapters (ADR-040):
- `AppKitWorkspaceAdapter` hops to the main actor inside each async method.
- `NSAppleScriptRunner` runs scripts on its own `Thread`, so a blocked script never holds the main thread or the cooperative pool.
- `FoundationProcessRunner` and `NSAppleScriptRunner` wait through `CompletionSignal`, a cancellation-aware one-shot value, and never block a thread while waiting.
