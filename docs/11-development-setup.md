# Development setup

How to get from a fresh clone to a green `make verify`. Everything here was run on 2026-10-17.

## Prerequisites

| Tool | Version verified | Install |
|---|---|---|
| macOS | 27.0 (build 26A428) | Deployment target is 14.0; any newer macOS can build |
| Xcode | 27.1 (27A9275), Swift 6.4 | App Store, then `sudo xcode-select --switch /Applications/Xcode.app` |
| Homebrew | 7.0.9 | https://brew.sh |
| XcodeGen | 2.46.0 | `brew install xcodegen` |
| SwiftLint | 0.65.1 | `brew install swiftlint` |
| swift-format | 604.0.0 | `brew install swift-format` |
| GitHub CLI | any recent | `brew install gh`, then `gh auth login` |

CI uses the GitHub-hosted image `macos-26` with its default Xcode (26.6 on 2026-10-17) and whatever versions of the three Homebrew tools are current; the workflow prints every version at the start of each run. Lint and format results can change between tool versions. When CI and local runs disagree, compare the printed versions first.

The `ModeKit` manifest uses `swift-tools-version: 6.0` so that both toolchains can read it (ADR-024).

## First run

```
git clone git@github.com:imyaxx/Presenter.git
cd Presenter
make generate
make verify
```

`make generate` creates `PresenterApp.xcodeproj` from `project.yml`. The project file is never committed. XcodeGen lists source files at generation time, so regenerate after changing `project.yml` and after adding, moving or deleting a file. `make build` and `make test` regenerate only when `project.yml` is newer than the project; `make verify` always regenerates. Running `xcodegen` twice gives an identical project.

Open `PresenterApp.xcodeproj` in Xcode to run the app with the debugger. Build products go to `.build/DerivedData` when built through `make`.

## Daily commands

| Command | Does |
|---|---|
| `make generate` | XcodeGen: `project.yml` to `PresenterApp.xcodeproj` |
| `make lint` | SwiftLint in strict mode over `App` and `Packages` |
| `make format` | swift-format in place over `App` and `Packages` |
| `make build` | `xcodebuild build` of the `PresenterApp` scheme |
| `make test` | `swift test` for `ModeKit`, then `xcodebuild test` for `PresenterAppTests` |
| `make verify` | generate, lint, format check (non-mutating), build, test; stops at the first failure |

`make verify` passes before every commit. `xcodebuild` runs with `-quiet`, so a green run prints no test counts for the app target; run `xcodebuild -project PresenterApp.xcodeproj -scheme PresenterApp -destination "platform=macOS,arch=$(uname -m)" test` without `-quiet` to see them.

Run the built app with a different language:

```
open -n .build/DerivedData/Build/Products/Debug/Presenter.app --args -AppleLanguages "(ru)"
```

## Running the app

Build and launch the Debug app through `open`, so macOS attributes the process, and its Automation prompt, to the app bundle:

```
make build
open .build/DerivedData/Build/Products/Debug/Presenter.app
```

The app has no Dock icon; its icon appears in the menu bar. A second launch only brings the running one forward. Quit from the popover or with Cmd+Q; both restore an active session first.

Profiles live in `~/Library/Application Support/dev.imyaxx.presenter/profiles.json` (the support directory named after the bundle identifier; `session.json` is written next to it while a profile is active). **Show Profiles in Finder** in the popover creates and opens that folder. The popover reloads the file each time it opens, so a hand-edited file shows without a relaunch. The format is in `docs/12-data-formats.md`.

A sample with two profiles:

```json
{
  "schemaVersion" : 1,
  "profiles" : [
    {
      "id" : "C0000000-0000-4000-8000-000000000001",
      "name" : "Quick",
      "steps" : [ { "type" : "hideDesktopIcons" }, { "type" : "hideMenuBar" } ]
    },
    {
      "id" : "C0000000-0000-4000-8000-000000000002",
      "name" : "Full",
      "steps" : [
        { "type" : "hideDesktopIcons" },
        { "type" : "hideDock" },
        { "type" : "hideMenuBar" },
        { "type" : "hideApps", "exclusions" : [] },
        { "type" : "wallpaper",
          "choice" : { "type" : "solidColor", "red" : 38, "green" : 38, "blue" : 38 },
          "displays" : { "type" : "allDisplays" } }
      ]
    }
  ]
}
```

"Full" hides every visible app except the frontmost one, Presenter, and the bundle identifiers listed in `exclusions`. For example, add `"com.apple.Safari"` to keep Safari on screen. The wallpaper is a neutral dark gray on the current Space of every display. The first activation of "Full" asks for permission to control System Events, for the Dock (Allow).

If something is left changed, quit the app first; it restores an active session on quit and on the next launch. If that is not enough, the adapter check scripts restore independently of the app (`docs/13-adapter-check.md`):
1. Take a backup with `Scripts/adapter-check-backup.sh` **before** experimenting.
2. If needed, restore with `Scripts/adapter-check-restore.sh <backup>`.
3. Check with `Scripts/adapter-check-diff.sh <backup>`.

## Troubleshooting

Problems actually hit while bootstrapping, with the fix in place.

- **A tool is missing, Xcode is not selected, or the Xcode license is not accepted.** `Scripts/require-tools.sh` runs before each make target and prints one line with the fix, for example `brew install swiftlint` or `sudo xcodebuild -license accept`. The license check uses `xcodebuild -license check` (exit 0 when accepted, verified on Xcode 27.1).
- **`xcodebuild: WARNING: Using the first of multiple matching destinations`.** Apple silicon Macs expose an arm64 and an x86_64 macOS destination. The Makefile passes `arch=$(uname -m)`.
- **`Could not find test host for PresenterAppTests`.** The app product is named after `PRODUCT_DISPLAY_NAME` (`Presenter.app`), not after the target. `project.yml` sets `TEST_HOST` explicitly; keep it in sync if the naming settings change.
- **SwiftLint `trailing_comma` and swift-format disagree.** swift-format owns trailing commas, so the SwiftLint rule is disabled. swift-format 604 also adds trailing commas to multi-line argument lists, which needs Swift 6.1 or newer.
- **`appintentsmetadataprocessor ... warning: Metadata extraction skipped`.** Printed by Xcode's App Intents step for any target without App Intents. It is not a compiler warning and does not fail the build.
- **`Unable to get synchronousRemoteObjectProxy ... com.apple.linkd.autoShortcut` during `make test`.** System log noise from the test host app at launch. Tests are unaffected.
- **Hardened runtime flag missing from a local build.** Expected: Xcode does not apply `--options runtime` when it signs ad hoc (`CODE_SIGN_IDENTITY = -`), even with `ENABLE_HARDENED_RUNTIME = YES`. See `docs/07-macos-integration.md`.
