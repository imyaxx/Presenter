You are a senior macOS and Swift engineer with more than 15 years of experience shipping production software. You write clean, stable, readable code with precise names and clear architecture. You do not write demo-quality or "vibe" code. You verify your work before declaring it done. You never state a platform fact you have not observed. You are working in an existing repository with strict rules.

## Context to read first (mandatory, in order)
1. CLAUDE.md
2. docs/STATUS.md
3. docs/README.md, then: docs/01-architecture.md (layers, domain model, action contract, persistence, error policy), docs/02-project-structure.md (ModeKit folder layout, naming), docs/03-code-standards.md (all of it; limits are enforced), docs/06-testing.md (persistence atomicity, fakes, coverage), docs/09-decisions.md (ADR-004, 007, 008, 011, 021, 024, 027), docs/05-git-workflow.md, docs/10-claude-code-protocol.md
4. Packages/ModeKit (the existing skeleton: Package.swift, SchemaVersion.swift and its test)
Do not start until you have read them. If anything here contradicts the docs, stop and report it.

## Objective
Create the data layer of ModeKit: the typed domain models, the one system port that persistence needs, an atomic file store, and the `ProfileStore` and `SessionStore` that read and write `profiles.json` and `session.json` with an explicit schema version and a safe policy for corrupted or newer files. After this branch, the session controller (next branch) can persist and recover state without changing any model or file format. Foundation only. No UI, no platform code, no actions.

## Scope (do exactly this)
All code under `Packages/ModeKit/Sources/ModeKit/`, tests under `Packages/ModeKit/Tests/ModeKitTests/`, following the folder layout in docs/02.

1. `Model/` (all `public`, `Sendable`, `Codable`, `Hashable` where useful, `///` documented):
   - `Profile { id: UUID, name: String, steps: [ProfileStep], autoExit: AutoExit? }`. The array order is the apply order. Name rules in item 2.
   - `ProfileStep`: `hideDesktopIcons`, `hideDock`, `hideMenuBar`, `hideApps(exclusions: Set<BundleIdentifier>)`, `wallpaper(WallpaperChoice, displays: DisplaySelection)`. No Focus step in this branch (it arrives with its action).
   - `WallpaperChoice`: `solidColor(SolidColor)`, `image(URL)` where the URL is a file URL and is encoded as a path string.
   - `SolidColor { red, green, blue: UInt8 }` (8-bit sRGB, no AppKit).
   - `DisplaySelection`: `allDisplays`, `specific(Set<DisplayIdentifier>)` (non-empty).
   - `DisplayIdentifier` (wraps a `UUID`, the display UUID; stability across reboot is unverified, see docs/07), `BundleIdentifier` (validated string, see item 2), `AutoExit` (whole seconds, see item 2, with a `duration: Duration` accessor), `ActionIdentifier` (`desktopIcons`, `dock`, `menuBar`, `hideApps`, `wallpaper`, String raw values) and `ProfileStep.actionIdentifier`.
2. Validation, in one type `ProfileValidation` with a typed `ProfileValidationError` enum:
   - Name: after trimming whitespace, 1 to 60 characters. The stored name is the trimmed one.
   - Steps: each step kind at most once per profile; `hideApps` exclusions are valid `BundleIdentifier`s; `DisplaySelection.specific` is non-empty; wallpaper `image` URL is a file URL.
   - `BundleIdentifier` init validates a strict reverse-DNS pattern (ASCII letters, digits, hyphen; at least two dot-separated labels; labels do not start or end with a hyphen; at most 255 characters) and is the allowlist that later keeps values out of AppleScript injection. Decoding an invalid value fails.
   - `AutoExit`: 60 to 86 400 seconds.
3. JSON format (stable, hand-writable, pretty-printed with sorted keys, dates ISO 8601). Every enum is coded with an explicit `type` discriminator, never with synthesized enum coding. Profiles file shape:

```json
{
  "schemaVersion": 1,
  "profiles": [
    {
      "id": "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21",
      "name": "Screen share",
      "autoExitSeconds": 1800,
      "steps": [
        { "type": "hideDesktopIcons" },
        { "type": "hideDock" },
        { "type": "hideMenuBar" },
        { "type": "hideApps", "exclusions": ["com.apple.Safari"] },
        { "type": "wallpaper",
          "choice": { "type": "solidColor", "red": 21, "green": 21, "blue": 21 },
          "displays": { "type": "allDisplays" } }
      ]
    }
  ]
}
```
   `autoExitSeconds` is omitted when nil. `exclusions` is written as a sorted array. A `specific` selection is `{ "type": "specific", "displays": ["<uuid>", ...] }`, an image choice is `{ "type": "image", "path": "/abs/path.png" }`. Unknown `type` values fail decoding.
4. `Ports/FileStore.swift`: `public protocol FileStore: Sendable` with `read(_ url: URL) async throws -> Data?` (nil when the file does not exist), `write(_ data: Data, to url: URL) async throws` (atomic), `remove(_ url: URL) async throws` (no error when absent). Document that local file I/O has no timeout by design (not an external wait).
5. `Persistence/FileManagerFileStore.swift`: the real implementation, Foundation only, `final class`/struct `Sendable`. Atomic write: create the parent directory if needed, write to a temporary file in the same directory, flush it to disk (`fsync`), replace the target atomically, so a failure at any step leaves the previous file intact and leaves no temporary file behind. It lives in ModeKit (not in Platform) because it needs only Foundation; this is ADR-029 (item 9).
6. `Persistence/ProfileStore.swift`: `public actor ProfileStore` built with `init(fileStore: any FileStore, directory: URL)` (the directory is injected by the composition root; ModeKit never resolves paths or reads `Bundle`). API: `loadProfiles() async throws -> [Profile]` (missing file = empty array), `saveProfiles(_ profiles: [Profile]) async throws` (validates every profile and that profile IDs are unique, then writes). File name `profiles.json`.
7. `Session/SessionRecord.swift`, `Session/ActionRecord.swift` and `Persistence/SessionStore.swift`: `SessionRecord { sessionID: UUID, profileID: UUID, profileName: String, startedAt: Date, actions: [ActionRecord] }`, `ActionRecord { identifier: ActionIdentifier, snapshotData: Data, appliedData: Data? }` (`appliedData` is nil until the action has been applied; `Data` is base64 in JSON). `public actor SessionStore` with the same init shape, `loadSession() async throws -> SessionRecord?`, `saveSession(_:) async throws`, `clearSession() async throws`. File name `session.json`, file shape `{ "schemaVersion": 1, "session": { ... } }`.
8. `Persistence/StoreError.swift`: typed `StoreError: Error, Sendable` with at least `unsupportedSchemaVersion(found: Int, supported: Int)`, `corrupted(fileName: String, reason: String)`, `invalidProfile(ProfileValidationError)`, `duplicateProfileID(UUID)`, `ioFailure(fileName: String, reason: String)`. Errors carry file names, never full paths.
9. Shared file policy, implemented once (a small internal type used by both stores, not copied):
   - Read: decode the `schemaVersion` header first. Newer than `SchemaVersion.current` throws `unsupportedSchemaVersion` and the file is never touched. Undecodable or invalid content throws `corrupted`. Older versions: no migration exists yet; the only version is 1, so older cannot occur; state this in a comment and do not write speculative migration code.
   - Write: before writing, read the existing file's header. A newer version refuses the write (`unsupportedSchemaVersion`). For `ProfileStore`, an undecodable existing file is first preserved byte for byte as `profiles.json.corrupt` (one backup, replaced if it exists), then overwritten. For `SessionStore`, an undecodable existing file refuses the write with `corrupted`, because a session file nobody understands may describe system changes that were never reverted; the caller must resolve it explicitly (`clearSession`).
   - `clearSession` removes the file regardless of its content.
   - Pre-release rule: schema version stays 1 while no release exists; shapes may still change in the next branch without a migration. Record this and the policy above as ADR-029 and ADR-030 (below).
10. Replace the placeholder content only where needed; keep `SchemaVersion` as it is and use `SchemaVersion.current` everywhere.

## Out of scope (do not do)
- `SessionController`, the state machine, recovery, the timer, any `ModeAction` or `AnyModeAction` (next branches).
- Ports other than `FileStore` (`DefaultsStore`, `ProcessRunner`, `AppleScriptRunner`, `WorkspaceAdapter`, `Clock`, `DistributedNotifier` are added by the branch that first needs them).
- Anything in `App/`, any UI, any Platform adapter, any Focus step.
- Profile CRUD helpers (add, rename, delete, reorder): M3.
- Changing the apply-order semantics. Observed conflict to report, not fix: docs/00-product-brief.md says actions apply "in a fixed order", docs/01-architecture.md says "in profile order". This branch stores the order as the array order and makes no claim beyond that; list the conflict under "Observed but not done".

## Requirements
- Architecture: ModeKit imports Foundation only. No third-party packages. `git grep -nE "import (AppKit|SwiftUI|CoreGraphics|ServiceManagement)" Packages/ModeKit` must print nothing.
- Code: follow docs/03-code-standards.md. No TODOs, no stubs, no commented-out code, no unrequested abstractions, no `Utils`/`Helpers`/`Manager` names, no boolean parameters, no force unwraps, no `try?` that discards a failure, no `print`. Files at most 300 lines, functions at most 50. Public API documented with `///` (behavior, errors, threading).
- Concurrency: stores are actors (serialized read-modify-write). Models are value types and `Sendable`. Swift 6 strict concurrency, zero warnings.
- Names: use exactly the type and file names above; vocabulary is profile, session, snapshot, action, step.
- Edge cases to handle explicitly: missing file; empty file; truncated JSON; valid JSON with wrong shape; unknown `type` value; unknown future `schemaVersion`; duplicate step kinds; empty or too long name; invalid bundle identifier; empty `specific` display set; image URL that is not a file URL; duplicate profile IDs; two concurrent saves; write failure during replace; Unicode names (Cyrillic, emoji); `Data` snapshots of several hundred kilobytes in `ActionRecord`.
- Not in scope for UI, so no L10n and no tokens.

## Acceptance criteria
- [ ] `make verify` passes with zero warnings; `swift test --package-path Packages/ModeKit` passes.
- [ ] The JSON example in this prompt decodes to the expected model and re-encodes byte-identical after normalizing the example's UUID and key order (use sorted keys in the expected fixture).
- [ ] A newer `schemaVersion` file is never modified by any `ProfileStore` or `SessionStore` call except `clearSession`.
- [ ] A write that fails leaves the previous file byte-identical and no temporary file in the directory.
- [ ] No import other than Foundation in `Packages/ModeKit` (grep above is empty).
- [ ] Coverage of the new ModeKit code is at least 90% with meaningful assertions (report the number and how you measured it).
- [ ] `docs/12-data-formats.md` exists and matches the code.

## Test plan
- Automated (Swift Testing, `Tests/ModeKitTests/`, mirroring source paths, names describe behavior): model round trips for every step kind; validation failures for each rule; `BundleIdentifier` accepts and rejects a table of cases; decoding rejects unknown `type`; `ProfileStore` and `SessionStore` against `InMemoryFileStore` (load missing, save then load, newer version refused, corrupted handling per the policy including the `.corrupt` backup, duplicate IDs, invalid profile, concurrent saves are serialized); `FileManagerFileStore` integration tests in a unique temporary directory (atomic replace, parent directory creation, remove when absent, failure leaves old file intact: for example by making the directory read-only for the failing write, and restore permissions in cleanup); `SessionRecord` with a 500 KB snapshot round trips.
- Support code in `Tests/ModeKitTests/Support/`: `InMemoryFileStore` with failure injection (fail the next read, write or remove), and builders for `Profile` and `SessionRecord`. No mocks of the units under test.
- Commands: `make verify`.
- Manual QA: none applies (no platform code). State that in the report.

## Git instructions
- Start from an up-to-date main: `git fetch origin --prune; git switch main; git pull --ff-only`.
- This prompt file is untracked in the working tree. Create branch `feat/modekit-models-and-persistence`, then make this file the first commit: `docs(prompts): add M1 models and persistence prompt`.
- Then commit atomically with Conventional Commits, tests in the same commit as the code they cover, every commit passing `make verify`. Suggested order: models and validation; FileStore port, `FileManagerFileStore` and the test fakes; `StoreError`, the shared file policy and `ProfileStore`; `SessionRecord`, `ActionRecord` and `SessionStore`; docs. Use scope `session` for every code commit (there is no `persistence` scope in docs/05) and `docs` for the docs commit.
- Stage files explicitly (never `git add .` or `-A`). Read `git diff --cached` before each commit. Never `--no-verify`.
- Push the branch and open a PR titled "feat(session): add ModeKit models and persistence" using `.github/pull_request_template.md`. Do not merge.

## Docs to update in the same branch
- New `docs/12-data-formats.md`: the profiles and session file formats (the example above), field rules, the validation rules, schema version and the pre-release rule, the corrupted and newer-file policy, and how a power user edits `profiles.json` safely. Link it from `docs/README.md`.
- `docs/09-decisions.md`: ADR-029 "Real `FileStore` lives in ModeKit (Foundation only), not in Platform" and ADR-030 "On-disk format and file policy" (explicit `type` discriminators, schema version 1 stays mutable until the first release, newer file refused, `.corrupt` backup for profiles, session file never overwritten when undecodable). Each: context, decision, consequence, "proposed by the assistant; user to confirm".
- `docs/01-architecture.md`: the `FileStore` row (real implementation in ModeKit), `Profile.autoExit` shape (`AutoExit` whole seconds) and the final model shapes.
- `docs/02-project-structure.md`: add the new files to the tree where they differ.
- `docs/STATUS.md`: M1 first branch done, next branch `feat/modekit-session-controller`, open decisions.

## Report format
Branch, Commits, Files changed, make verify result (with test counts and coverage), Manual QA, Docs updated, Observed but not done (include the apply-order conflict), Unverified, Next step (see docs/10-claude-code-protocol.md).
