# Code standards

Swift 6 language mode with strict concurrency. Warnings are errors in CI.

## Limits

- File at most 300 lines. Function at most 50 lines. Nesting at most 3 levels.
- Type with more than 7 stored properties or more than one reason to change gets split.
- Parameters: at most 4. More means a parameter struct.

## Naming

- Types and protocols: `UpperCamelCase` nouns. Functions: verb + noun (`captureSnapshot`, `applyWallpaper`). Booleans read as assertions: `isActive`, `hasPendingRestore`.
- No abbreviations except universally known ones (`URL`, `ID`, `UI`). `cfg`, `mgr`, `vm`, `ctx`, `btn`, `res`, `req`, `tmp`, `data`, `info`, `item`, `obj`, `val` are banned unless qualified (`profileData` is acceptable if `Data` carries a profile).
- No `Manager`, `Helper`, `Util`, `Handler`, `Processor` suffixes. Name the actual responsibility.
- Consistent vocabulary: "profile", "session", "snapshot", "action", "step". Do not introduce synonyms (`mode`, `preset`, `scene`).
- One naming style per file; no drift.

## Types and APIs

- Prefer `struct` and `enum`. `final class` only when identity or reference semantics are required. `actor` for owned mutable state accessed concurrently.
- Models are immutable by default. `let` unless mutation is required.
- Enums with associated values over stringly-typed state. `String` raw values only at serialization boundaries.
- No boolean parameters. Use two functions or an option enum. `apply(forced: true)` is rejected.
- Access control explicit at module boundaries: `public` only in `ModeKit` APIs that the app consumes; default `internal`; `private` for helpers. `fileprivate` needs a reason.
- No force unwrap (`!`), no `try!`, no implicitly unwrapped optionals (except `@IBOutlet`-style framework requirements, which we do not use). `fatalError` only for provably unreachable code with an explanatory message.
- No `Any` or `AnyObject` as escape hatches. Type erasure only where the architecture requires it and only inside ModeKit.

## Errors

- Typed errors per component, `enum ... : Error, Sendable`, with cases that carry enough context to produce an actionable message.
- One strategy per module: ModeKit throws. The UI layer maps errors to localized messages in the view model.
- No empty `catch`. No `try?` that discards failure information, unless the absence is a valid outcome and a comment states why.
- Errors never carry sensitive paths in user-visible text.

## Concurrency

- `async`/`await` and actors. No `DispatchQueue` in new code, no `Task.detached` without a documented reason, no fire-and-forget `Task {}` without error handling.
- UI types are `@MainActor`. Platform adapters that require the main thread declare it explicitly.
- Every external wait (process, AppleScript, file I/O) has a timeout and cancellation handling.
- No global mutable state, no singletons, no `static var`.

## State and views

- View models are `@Observable` and `@MainActor`, hold view state and intents, contain no system calls and no formatting of localized text beyond calling `L10n`.
- Views are declarative and small. A view body over 60 lines is split into subviews. No logic in `body` beyond layout and trivial conditionals.
- Derived state is computed, not stored.
- State lives at the lowest level that needs it. No passing a value through more than two view levels; use the environment or restructure.
- Views never read `UserDefaults`, `FileManager`, `NSWorkspace`, or run processes.

## Comments and docs

- Comments explain non-obvious WHY (a macOS quirk, a deliberate ordering). They never restate the code.
- Public ModeKit APIs have `///` documentation covering behavior, errors, and threading.
- No `TODO`, `FIXME`, commented-out code, or "temporary" code on any branch that is merged.
- Platform quirks go to `docs/07-macos-integration.md` with the macOS version they were verified on.

## Logging

`os.Logger` only. No `print`. Levels: `debug` (development detail), `info` (state transitions), `error` (failures). Never log user file contents or personal data. Use privacy annotations.

## Constants and configuration

- No magic numbers or strings. Named constants in the owning type or in `DSSpacing`-style token namespaces.
- No hard-coded paths. Resolve through `FileManager` URLs. No hard-coded bundle identifiers; read from `Bundle.main`.

## Security and safety

- Never build shell command strings. Use `Process` with `executableURL` and an arguments array.
- Never interpolate user input into AppleScript source. Pass values as parameters or validate against an allowlist (bundle IDs match a strict pattern).
- Validate every external input: file contents, JSON from disk, hotkey values.
- Write files atomically. Never leave a half-written `session.json`.
- The app makes no network requests.

## Formatting and lint

- `swift-format` is the formatter, config in `.swift-format`. `SwiftLint --strict` is the linter, config in `.swiftlint.yml`. Both run in CI and in `make verify`.
- Imports sorted, one per line. Trailing commas per swift-format. Line length 120.
- Never disable a lint rule inline without a one-line justification and a link to a decision.

## Review checklist (self-review before every commit)

1. Does each type have exactly one job and a precise name?
2. Are system calls only behind ports?
3. Is every failure path handled and tested?
4. Are there user-visible strings or colors outside the token and localization layers?
5. Could any step leave the user's Mac in a changed state without a persisted snapshot?
6. Is there dead code, a TODO, or an unused parameter?
7. Does `make verify` pass from a clean checkout?
