# Project structure

## Target tree

```
.
├── CLAUDE.md
├── LICENSE                      # MIT
├── Makefile
├── project.yml                  # XcodeGen spec; the .xcodeproj is generated, never committed
├── .swiftlint.yml
├── .swift-format
├── .editorconfig
├── .gitignore
├── .github/
│   ├── workflows/ci.yml
│   └── pull_request_template.md
├── docs/
├── Scripts/                     # small, documented shell scripts called by Makefile
├── Packages/
│   └── ModeKit/                 # domain core, Foundation only
│       ├── Package.swift
│       ├── Sources/ModeKit/
│       │   ├── Model/           # Profile, ProfileStep, WallpaperChoice, SolidColor, DisplaySelection,
│       │   │                    # DisplayIdentifier, BundleIdentifier, AutoExit, ActionIdentifier,
│       │   │                    # ProfileValidation, ProfileValidationError
│       │   ├── Actions/         # one file per type: DesktopIconsAction(+Error), DockAction(+Error),
│       │   │                    # StandardActionFactory; more actions follow
│       │   ├── Session/         # SessionController (+Restoration, +Recovery, +Degraded), SessionState,
│       │   │                    # ActiveSession, DegradedReason, RestoreReport, RecoveryOutcome, TriggerResult,
│       │   │                    # SessionError, ActionFailure, ActionError, contract (ActionRestorer, ModeAction,
│       │   │                    # ActionFactory, RestoreOutcome), SystemSessionClock, SessionRecord, ActionRecord;
│       │   │                    # internal: AnyModeAction, AnyActionRestorer, CapturePass, ApplyPass,
│       │   │                    # RestorePass, StatePublisher
│       │   ├── Persistence/     # ProfileStore, SessionStore, FileManagerFileStore (ADR-029), StoreError,
│       │   │                    # SchemaVersion; internal: VersionedJSONFile (shared file policy),
│       │   │                    # VersionedFileEnvelope, ProfilesFile, SessionFile, UndecodableFilePolicy,
│       │   │                    # PersistenceCoding, TaskSerializer
│       │   └── Ports/           # protocols for system access: FileStore, SessionClock, SessionLogger,
│       │                        # DefaultsStore (DefaultsKey, DefaultsValue, DefaultsError), ProcessRunner
│       │                        # (ProcessCommand, ProcessResult, ProcessError), AppleScriptRunner
│       │                        # (AppleScript, AppleScriptError)
│       │                        # (with SessionEvent)
│       └── Tests/ModeKitTests/
│           ├── Model/
│           ├── Actions/
│           ├── Session/
│           ├── Persistence/
│           ├── Ports/
│           └── Support/         # fakes and builders shared by tests (InMemoryFileStore, ProfileBuilder,
│                                # SessionRecordBuilder, FakeModeAction, FakeActionFactory, FakeClock,
│                                # RecordingSessionLogger, AsyncGate, SessionControllerHarness,
│                                # FakeDefaultsStore, FakeProcessRunner, FakeAppleScriptRunner,
│                                # StandardActionsHarness)
└── App/
    ├── Sources/
    │   ├── Application/         # @main, AppDelegate, AppEnvironment (composition root)
    │   ├── Platform/            # real implementations of ModeKit ports
    │   │   ├── Defaults/
    │   │   ├── Process/
    │   │   ├── AppleScript/
    │   │   ├── Workspace/
    │   │   ├── Hotkey/
    │   │   └── LoginItem/
    │   ├── Features/            # one self-contained folder per feature
    │   │   ├── MenuBar/         # MenuBarView, MenuBarViewModel
    │   │   ├── Hud/
    │   │   ├── Settings/
    │   │   │   ├── Profiles/
    │   │   │   ├── General/
    │   │   │   ├── Appearance/
    │   │   │   └── Permissions/
    │   │   └── Onboarding/
    │   ├── DesignSystem/
    │   │   ├── Tokens/          # DSColor, DSSpacing, DSTypography, DSRadius, DSMotion
    │   │   ├── Theme/           # AppearancePreference, ThemeController
    │   │   └── Components/      # DSButton, DSToggleRow, DSSectionHeader, DSEmptyState, ...
    │   └── Localization/        # L10n namespaces, one file per feature (L10n+Settings.swift, ...)
    ├── Resources/
    │   ├── Assets.xcassets      # colors (light/dark variants), app icon, menu-bar icons
    │   ├── Localizable.xcstrings   # String Catalog: en (source), ru
    │   └── Presenter.entitlements   # Info.plist is generated from project.yml build settings
    └── Tests/                   # view-model tests for the app target
```

## Dependency rules (enforced in review)

1. `ModeKit` imports Foundation only. No AppKit, no SwiftUI, no third-party packages.
2. `Features/*` never import `Platform/*`. Features receive protocols and are built in `Application/`.
3. `DesignSystem` never imports `Features`, `ModeKit`, or `Platform`.
4. Features never import each other. Shared UI goes to `DesignSystem/Components`; shared logic goes to `ModeKit`.
5. Only `Application/` instantiates concrete platform types.
6. No `Utils`, `Helpers`, `Common`, or `Manager` folders or types. If a name needs one of those words, the responsibility is not understood yet.

## Separation of concerns for UI

| Concern | Lives in | Never in |
|---|---|---|
| Colors, spacing, type scale, radii, motion | `DesignSystem/Tokens` + `Assets.xcassets` | Views |
| Reusable controls and rows | `DesignSystem/Components` | Features |
| Appearance preference and its application | `DesignSystem/Theme` | Views |
| User-visible strings | `Localizable.xcstrings` + `Localization/L10n+*.swift` | Views, view models |
| Screen layout and view state | `Features/<Name>/` | DesignSystem |
| System calls | `Platform/` | Features, ModeKit |

## File naming

- One primary type per file; the file is named after the type.
- Extensions: `Type+Topic.swift`.
- Protocols named by role (`DefaultsStore`), not with `Protocol` suffix. Implementations named by mechanism (`UserDefaultsStore`, `ShellProcessRunner`).
- View models end with `ViewModel`. Views end with `View`.
- Tests mirror the source path and end with `Tests`. Test names describe behavior: `restoresDockAutohideWhenUserDidNotChangeItMeanwhile`.

## Targets (project.yml)

| Target | Type | Notes |
|---|---|---|
| `PresenterApp` | macOS application | `LSUIElement = YES`, hardened runtime, not sandboxed, deployment target 14.0 |
| `PresenterAppTests` | unit tests | App-layer view model tests |
| `ModeKit` | local Swift package | Tested with `swift test` |

The product display name and bundle identifier are single build settings in `project.yml` (`PRODUCT_DISPLAY_NAME`, `APP_BUNDLE_IDENTIFIER`). Renaming the product must be a one-place change (ADR-020). The built app is named after `PRODUCT_DISPLAY_NAME` (`Presenter.app`); the Swift module stays `PresenterApp`. `Info.plist` is not a file in the repository: `GENERATE_INFOPLIST_FILE` builds it from `INFOPLIST_KEY_*` settings, so it cannot drift from those settings.

## Third-party dependencies

Minimal and justified in `docs/09-decisions.md`. Approved: `KeyboardShortcuts` (MIT, hotkey recorder; verify maintenance status and macOS 14 support before adding). Dev tools (not linked): XcodeGen, SwiftLint, swift-format. Any other dependency requires a decision record first.
