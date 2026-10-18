# Data formats

The two files ModeKit persists, their rules, and the policy for unexpected content. The code is the source of truth: `Packages/ModeKit/Sources/ModeKit/Model/`, `Session/` and `Persistence/`. Decisions: ADR-029 and ADR-030 in `docs/09-decisions.md`.

## Location and writing

Both files live in one directory that the composition root passes to the stores (planned: `~/Library/Application Support/<bundle identifier>/`, `docs/01-architecture.md`). ModeKit never resolves paths itself.

Every write is atomic. The new content goes to a temporary file in the same directory, is flushed with `fsync`, then replaces the target with `rename(2)`. A failed write leaves the previous file byte-identical and leaves no temporary file behind.

The app writes JSON pretty-printed with sorted keys, unescaped slashes, ISO 8601 dates with whole seconds, and base64 binary data. Hand-written files may use any key order and whitespace.

## `profiles.json`

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

Fields of a profile:

| Field | Type | Rule |
|---|---|---|
| `id` | UUID string | Unique within the file. |
| `name` | string | 1 to 60 characters (grapheme clusters, so an emoji counts as one) after trimming whitespace and newlines; stored trimmed. |
| `autoExitSeconds` | integer | Optional; omitted means off. 60 to 86 400. |
| `steps` | array | Apply order is the array order. Each step `type` at most once. May be empty. |

Steps are objects with a `type` discriminator:

| `type` | Other fields |
|---|---|
| `hideDesktopIcons` | none |
| `hideDock` | none |
| `hideMenuBar` | none |
| `hideApps` | `exclusions`: array of bundle identifiers, written sorted |
| `wallpaper` | `choice` and `displays`, below |

`choice` is `{ "type": "solidColor", "red": 0-255, "green": 0-255, "blue": 0-255 }` (8-bit sRGB) or `{ "type": "image", "path": "/absolute/path.png" }`. The image path must be absolute.

`displays` is `{ "type": "allDisplays" }` or `{ "type": "specific", "displays": ["<display UUID>", ...] }` with at least one UUID, written sorted. Whether a display UUID stays stable across reboot is unverified (`docs/07-macos-integration.md`).

A bundle identifier is strict reverse DNS: ASCII letters, digits and hyphens only; at least two dot-separated labels; no empty label; no label starting or ending with a hyphen; at most 255 characters. `com.apple.Safari` passes; `com.app_le`, `safari` and anything with spaces or quotes fail. This rule is the allowlist that keeps these values safe to use in AppleScript later.

An unknown `type` anywhere fails decoding. Every enumeration with fields uses a `type` discriminator, never the compiler-synthesized enum format.

## `session.json`

Written before any system change (ADR-007) and removed after a complete restore.

```json
{
  "schemaVersion" : 1,
  "session" : {
    "actions" : [
      {
        "identifier" : "dock",
        "snapshotData" : "eyJhdXRvaGlkZSI6dHJ1ZX0="
      }
    ],
    "profileID" : "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21",
    "profileName" : "Screen share",
    "sessionID" : "A0000000-0000-0000-0000-000000000001",
    "startedAt" : "2026-10-17T12:00:00Z"
  }
}
```

- `actions` is in apply order, one record per action.
- `identifier` is one of `desktopIcons`, `dock`, `menuBar`, `hideApps`, `wallpaper`.
- `snapshotData` is the action's encoded snapshot, base64. It is opaque to the store and may be several hundred kilobytes, for example a wallpaper store copy (ADR-027).
- `appliedData` is the encoded applied state, base64. It is omitted until the action has been applied.

## Schema version

`schemaVersion` is the first thing read. The only version is 1 (`SchemaVersion.current`).

Pre-release rule: while no release exists, version 1 stays mutable. A later branch may still change these shapes without a migration and without raising the version. From the first release on, every shape change raises the version and adds a migration in the same change.

## Unexpected content

| Situation | Load | Save |
|---|---|---|
| File missing | Empty profile list, or no session | Written |
| `schemaVersion` newer than this build | Refused (`unsupportedSchemaVersion`) | Refused; the file is never modified |
| Empty, truncated, not JSON, wrong shape, unknown `type`, `schemaVersion` below 1, or content that breaks a rule above | `corrupted` with the file name and a reason | Profiles: the file is copied byte for byte to `profiles.json.corrupt` (replacing an older copy), then overwritten. Session: refused with `corrupted`; the file is left untouched |
| Profiles passed to a save break a rule | n/a | Refused with `invalidProfile` or `duplicateProfileID`; nothing is written |

Only `clearSession` removes a session file whatever its content. A session file nobody understands may describe system changes that were never reverted, so it is never overwritten silently. Errors carry file names, never full paths.

## Editing `profiles.json` by hand

1. Quit the app, so it cannot save over your edit.
2. Copy `profiles.json` somewhere safe.
3. Edit it. Keep `"schemaVersion": 1`, give new profiles a fresh UUID (`uuidgen` prints one), and follow the rules above.
4. Check the syntax: `python3 -m json.tool profiles.json` prints the file on success and exits with status 1 and the position of the first error otherwise.
5. Start the app. If the file breaks a rule, loading fails with `corrupted` and a reason (how the app shows this is decided in M2). The next save keeps your version as `profiles.json.corrupt` before writing a valid file.
