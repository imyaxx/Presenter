# Adapter check

How to run the real adapters through the real session controller on a real Mac, under a backup, a diff and an independent restore, and how to repeat the whole protocol, for example on another macOS version or before a release. Decision: ADR-042. Results of each run go to the C-series entries of `docs/07-macos-integration.md`.

**This changes the real system: the desktop icons, the Dock, the menu bar, the wallpaper, and the visibility of applications the protocol opens itself. Never run it unattended.**

## The tool

A DEBUG-only mode of the app itself (`App/Sources/DeveloperTools/AdapterCheck/`, every file in `#if DEBUG`). Testing the real app bundle is the only way to see the real Automation prompt, with the app's name and its localized `NSAppleEventsUsageDescription`. A Release build contains no tool code.

When the app is launched with `--adapter-check <command> --result <file> ...`, it runs the command instead of its menu bar scene: no menu bar item, no window. It writes a JSON result file `{"status": "ok" | "failed", "command", "error", "details"}`, and writes JSON event lines to standard output (session events, and each `hide` or `unhide` with its result). Then it exits.

Always launch it through `Scripts/adapter-check.sh`. The script builds the Debug app and launches it with `open -n -W -a <app> --stdout ... --stderr ... --args ...`, as the M0 spike S4 launched its bundles (`open -n -W <bundle> --args ...`), so that macOS attributes the process, and the Automation prompt, to the app bundle. Because `open -W` does not return the program's exit code, the script prints the result file and exits nonzero when the status is not `ok`.

Script options, before the command:

| Option | Effect |
|---|---|
| `--no-build` | Skip the build |
| `--language ru` | Launch with `-AppleLanguages "(ru)"` |
| `--result-file <path>` | Write the result file to `<path>` |

Everything stays in the check directory, `~/presenter-check/` (or `$PRESENTER_CHECK_DIR`): `profiles.json`, `session.json`, generated wallpapers in `wallpapers/`, `results/` (result files, event lines, standard error), and `backup-<UTC timestamp>/`. The tool never touches the app's real support directory. This directory holds local data (application identifiers, display UUIDs, store copies): never commit anything from it.

### Commands

| Command | Changes the system | What it does |
|---|---|---|
| `world` | no | JSON snapshot. Schema version and macOS version. The five action keys, read through `CFPreferencesDefaultsStore` (type and value, or `absent`). The wallpaper store: size, SHA-256, and the inspector's fingerprint or its error. The regular applications with their hidden flag, sorted. The frontmost application, kept apart. The display UUIDs. |
| `store-structure` | no | The real wallpaper store's key names and value kinds, never values. Display and Space UUID keys are collapsed to a count. |
| `run --profile <name> [--hide-only <ids>] [--hold-seconds N]` | yes | Loads `profiles.json` from the check directory with the real `ProfileStore`, then runs `recoverIfNeeded`, `activate`, a hold of N seconds (default 8), and `deactivate`, and reports. Uses the real `SessionController` over `StandardActionFactory` with `PlatformComposition`'s ports, `SessionStore` in the check directory, and `OSSessionLogger` plus the printing logger. Refuses to start when recovery found an earlier session. |
| `run --hide-only <ids>` | yes | Without `--profile`: a single `hideApps` step whose exclusions are every running regular application except the listed ones. With `--profile`: restricts that profile's `hideApps` step the same way. A profile with a `hideApps` step is refused without `--hide-only`, because it could hide the user's own applications. |
| `activate --profile <name> [--hide-only <ids>] [--hold-seconds N]` | yes | As `run`, but exits after the hold (default 0) without deactivating, leaving `session.json` as a crash would. |
| `recover` | yes | A new process that only calls `recoverIfNeeded` and prints the outcome. |
| `wallpaper-latency [--runs N]` | yes | For each run (default 12): reads the store fingerprint; sets a generated solid color on every display through the adapter; polls the store every 10 ms until the inspector's fingerprint changes (cap 10 s); restores with `WallpaperRestorer` (`applied: nil`); waits 2 s. Prints each latency, the median, the 95th percentile and the poll count that the ADR-038 rule gives. |
| `wallpaper-interrupt` | yes | Sets a color through the adapter and at once restores with `applied: nil`. Reports whether the store had changed before the restore, whether it equals the baseline after the restore, and whether it still does 10 s later. |
| `notify-menubar` | yes | Posts `AppleInterfaceMenuBarHidingChangedNotification` through the real notifier (used by the emergency restore). |

Commands that change the system require `--backup <dir>` pointing at a backup made by the backup script less than 24 hours ago, whose `MANIFEST.json` lists files that exist. Otherwise they refuse and change nothing.

### Profiles

`Scripts/adapter-check-profiles.json` is copied to `~/presenter-check/profiles.json` the first time, with `__CHECK_DIR__` replaced:

| Profile | Steps |
|---|---|
| `desktop-icons` | desktop icons |
| `dock` | Dock |
| `menu-bar` | menu bar |
| `wallpaper-color` | wallpaper, `#1E90FF` on all displays |
| `wallpaper-image` | wallpaper, `~/presenter-check/image-check.png` on all displays |
| `all-five` | all five steps; needs `--hide-only` |

Delete the copy to get the template again.

## Scripts

| Script | Purpose |
|---|---|
| `Scripts/adapter-check.sh [options] <command> [tool options]` | Runs one tool command (above). |
| `Scripts/adapter-check-backup.sh [--screenshot]` | Creates `backup-<UTC>/` (contents below) and prints its path on the last line. |
| `Scripts/adapter-check-diff.sh <backup>` | Compares the current system with the backup (checks below). Exits 0 only if everything is equal, and prints each difference. |
| `Scripts/adapter-check-restore.sh <backup>` | Emergency restore, independent of the code under test (steps below). Use it only when `recover` cannot restore. |
| `Scripts/compare-wallpaper-store.swift <expected> <actual>` | Standalone store comparison: no ModeKit, no inspector. Decodes nested property lists and ignores `LastUse` only. |

The backup contains:
- `MANIFEST.json`;
- `defaults export` of `com.apple.finder`, `com.apple.dock`, `com.apple.controlcenter` and `NSGlobalDomain`;
- `keys.tsv`, the five keys read with `defaults read-type` and `defaults read`;
- the listing of the `com.apple.wallpaper` directory and a copy of `Index.plist`;
- `world.json`;
- `sw_vers.txt`.

A desktop screenshot is taken only with `--screenshot`: `screencapture` may ask for a privacy permission, which the protocol never requests.

The diff checks:
- the five keys against `keys.tsv`, exactly;
- the applications with their hidden flags, and the displays, against `world.json`;
- the wallpaper store with `compare-wallpaper-store.swift`.

The emergency restore:
1. Writes each key back with `defaults write`, or `defaults delete` when it was absent.
2. Runs `killall Finder` when `CreateDesktop` changed, and `killall Dock` when `autohide` changed (S5 and S4 mechanism B).
3. Copies `Index.plist` back and runs `killall WallpaperAgent`.
4. Posts the menu bar notification through the tool.
5. Prints what it did, and what to check by eye.

## Protocol

Every stage that changes the system follows the M0 cycle:
1. Take a baseline with `world`.
2. Tell the user in one line what will visibly happen, for how long, and how it is restored.
3. Run the stage.
4. Ask the user what they saw.
5. Let the session's own deactivate restore.
6. Run `adapter-check-diff.sh`.

If the diff is not empty, a command fails with a session active, or anything unexpected appears: run `recover`, then the diff again, and if needed the emergency restore. Report exactly what differs, and stop. Do not continue to the next stage.

Before starting, confirm that the user is at the Mac, has saved their work, and agrees to the visible effects. Do not change any other setting. Run `tccutil reset` only for `AppleEvents` and only for the app's bundle identifier. Never request or grant a privacy permission to any app.

| Stage | What | Expect |
|---|---|---|
| B0 | `adapter-check-backup.sh`; `world`. Ask about at least two Spaces, opening TextEdit and Calculator, a second display, and whether one app can go full screen. | Backup path printed. |
| B1 | `world` against `defaults read-type` / `defaults read` of the five keys, and the store SHA-256 against `shasum -a 256`. | Equal. Proves the `CFPreferences` reads. |
| B2 | `killall <name that does not exist>`. | The exit code. A found-but-unsignalled process cannot be produced: say so. |
| B3 | `run --profile desktop-icons --hold-seconds 8` | Icons disappear and return; `killall Finder` exits 0; the diff is empty. |
| B4 | Dock. `tccutil reset AppleEvents <app id>`, then `run --profile dock`. The user types the prompt text and its language, and chooses Allow. Then: reset and Don't Allow (`notAuthorized`, rolled back); reset and `--language ru` (Russian prompt text); reset and no answer (system -1712 after about 120 s, mapped to `timedOut`). Leave it allowed. | The prompt names the app and shows the usage description. |
| B5 | `run --profile menu-bar` on the desktop, then with an app in full screen. | The menu bar hides and returns in both; the diff is empty. |
| B6 | `open -a TextEdit; open -a Calculator`, then `run --hide-only com.apple.TextEdit,com.apple.calculator`. Variants: a second TextEdit instance (`open -n -a TextEdit`); the user unhides one app during the hold; the user unhides all; the user quits Calculator; TextEdit in full screen. | `hide` and `unhide` results in the event lines; outcomes as ADR-036 says; a quit app is not relaunched. |
| B7 | `store-structure`; `run --profile wallpaper-color --hold-seconds 10` (the user checks the other Space); `store-structure` during a hold; `wallpaper-latency --runs 12` (apply the calibration rule); `run --profile wallpaper-image`; `wallpaper-interrupt`; a second display if present. | The diff's store comparison is equal. |
| B8 | `run --profile all-five --hide-only <ids> --hold-seconds 15`; then `activate --profile all-five --hide-only <ids> --hold-seconds 120` in the background, `kill -9` the app, `recover`, diff. | Everything restored. |
| B9 | `run --profile all-five --hide-only <ids> --hold-seconds 60`. During the hold the user changes Dock auto-hide and the wallpaper in System Settings. | `dock` and `wallpaper` skipped; the user's values kept. Set them back, then the diff is empty. |
| B10 | `adapter-check-diff.sh <first backup>`. | Empty; list anything left and how to undo it. |

Reboot recovery and macOS 14 and 15 are outside this protocol.

## Repeating it

1. Check out the commit to verify and run `make verify`.
2. Delete `~/presenter-check/profiles.json` if the template changed.
3. Run B0 to B10 with the user present.
4. Record each stage in `docs/07-macos-integration.md` as a new entry, `### C<N> <date> macOS <version>`. Label every line **machine** or **human**, and record counts, shapes and timings only: no paths, user names, application identifiers of the user's own apps, display UUIDs or store contents.
5. Append a dated "Verified on this Mac" or "Corrected" note to each affected ADR.
