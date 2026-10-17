You are a senior macOS and Swift engineer with more than 15 years of experience shipping production software. You write clean, stable, readable code with precise names and clear architecture. You do not write demo-quality or "vibe" code. You verify your work before declaring it done. You are working in a repository with strict rules.

## Context to read first (mandatory, in order)
1. CLAUDE.md
2. docs/STATUS.md
3. docs/README.md
4. docs/02-project-structure.md, docs/03-code-standards.md, docs/05-git-workflow.md, docs/06-testing.md, docs/08-roadmap.md (section "Bootstrap"), docs/09-decisions.md
Do not start until you have read them. If anything here contradicts the docs, stop and report it.

## Objective
Turn the documentation-only folder into a buildable, linted, tested, CI-checked repository connected to GitHub, with an empty-but-real app skeleton and a ModeKit package skeleton. After this task, every later feature can be developed on a branch with `make verify` as the gate.

## Environment facts (verify, do not assume)
- Remote: `git@github.com:imyaxx/Presenter.git` (private, empty, no commits, no branch protection yet).
- Working directory: the project root (contains CLAUDE.md and docs/ only; not a git repository yet).
- Required tools: Xcode (stable), `xcodegen`, `swiftlint`, `swift-format`, `gh`. Run `xcodebuild -version`, `swift --version`, `xcodegen --version`, `swiftlint version`, `swift-format --version`, `gh auth status`, `ssh -T git@github.com`. If any fails, stop and tell me exactly which and the one-line fix. Do not install anything silently.
- Product codename is `Presenter` (temporary). App target: `PresenterApp`. Bundle identifier: `dev.imyaxx.presenter` (temporary, defined only in project.yml).

## Scope (do exactly this)

### Step 1: initial commit on main (documentation only)
1. `git init -b main`, add remote `origin`.
2. Create `.gitignore` first: Xcode (`*.xcodeproj`, `xcuserdata/`, `DerivedData/`, `*.xcworkspace` generated parts), SwiftPM (`.build/`, `.swiftpm/`), macOS (`.DS_Store`), editors, `*.log`. Verify with `git status` that nothing generated would be tracked.
3. Stage explicitly `.gitignore`, `CLAUDE.md`, `docs/`. Read `git diff --cached`. Commit: `docs: add project documentation and Claude Code instructions`.
4. Push `main` to origin (allowed now: the repository is empty and unprotected). This is the only direct push to main in the project's life.

### Step 2: bootstrap branch `chore/bootstrap-repository`
Create the branch from main and implement, as separate atomic commits in this order:

1. `chore(build): add license, editorconfig and tooling configs`
   - `LICENSE` (MIT, holder: repository owner's GitHub name `imyaxx`, year 2026), `.editorconfig` (UTF-8, LF, final newline, 4-space Swift, 2-space YAML/JSON/MD).
   - `.swiftlint.yml`: strict; enforce the limits in docs/03-code-standards.md (file length 300 error, function body 50, nesting 3, line length 120, force_unwrapping, force_try, force_cast as errors); a custom rule banning `print(` outside tests; included paths `App` and `Packages`.
   - `.swift-format`: line length 120, 4-space indentation, ordered imports, trailing commas.
2. `feat(build): add ModeKit package skeleton`
   - `Packages/ModeKit/Package.swift` (swift-tools-version matching the installed Swift, platform macOS 14, Swift 6 language mode, no dependencies), `Sources/ModeKit/Persistence/SchemaVersion.swift` with `public enum SchemaVersion { public static let current = 1 }`, documented with `///`.
   - `Tests/ModeKitTests/Persistence/SchemaVersionTests.swift` using Swift Testing with a meaningful assertion (the current version is positive and is the value later migrations will compare against).
   - Folder skeleton exactly as in docs/02-project-structure.md, only where files exist (do not create empty placeholder files).
3. `feat(build): add app skeleton and XcodeGen project`
   - `project.yml`: app target `PresenterApp` (macOS 14.0, Swift 6, `LSUIElement = YES`, hardened runtime on, App Sandbox off, bundle id and display name as the only places containing product naming besides the target name), local package dependency on `Packages/ModeKit`, unit test target `PresenterAppTests`, shared scheme, `GENERATE_INFOPLIST_FILE` or explicit `Info.plist` (your choice, justify in the commit body), `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
   - `App/Sources/Application/PresenterApp.swift`: `@main` with `MenuBarExtra` showing a real minimal popover: the product name and version (from `Bundle.main`) and a Quit button. No placeholder text, no TODOs.
   - `App/Sources/Localization/L10n.swift` (namespace `L10n.Menu` returning `LocalizedStringResource`) and `App/Resources/Localizable.xcstrings` with `en` (source) and `ru` for every key used, each with a translator comment.
   - `App/Resources/Assets.xcassets` with an app icon set placeholder-free minimum (a valid empty AppIcon set is acceptable) and a template menu-bar symbol (use an SF Symbol via `systemImage`; no custom asset yet).
   - `App/Resources/Presenter.entitlements`: hardened-runtime-compatible, no sandbox. Do not add Apple Events entitlements yet (added in the milestone that needs them).
   - `App/Tests/LocalizationCatalogTests.swift`: loads `Localizable.xcstrings` (locate via `#filePath`) and asserts every key has non-empty `en` and `ru` values.
4. `chore(build): add Makefile and verification scripts`
   - `Makefile` targets exactly: `generate`, `lint`, `format`, `build`, `test`, `verify` as defined in CLAUDE.md. `verify` = generate, lint, format check (non-mutating), build, test, failing on the first error. Use `xcodebuild` with `-destination 'platform=macOS'`; no reliance on a specific Xcode path.
   - `Scripts/` only if a script is genuinely needed; each script documented and `set -euo pipefail`.
5. `ci: add GitHub Actions workflow and pull request template`
   - `.github/workflows/ci.yml`: triggers on `pull_request` and push to `main`; one job on a macOS runner; checkout, install tools with Homebrew, run `make verify`. Pin the runner image label explicitly (check GitHub's currently available macOS labels from official docs; if you cannot verify, say so in the report). Cache Homebrew and SwiftPM where safe. Minimal `permissions: contents: read`.
   - `.github/pull_request_template.md` with the sections from docs/05-git-workflow.md.
6. `docs: add development setup guide and update status`
   - `docs/11-development-setup.md`: prerequisites, tool install commands, first run, daily commands, troubleshooting that you actually encountered. Add it to the table in `docs/README.md`.
   - Update `docs/STATUS.md` (milestone state: bootstrap done on branch, next: merge then M0) and `docs/02-project-structure.md` only if reality differs from the doc (state the difference).

## Out of scope (do not do)
Any product feature, any ModeKit domain type other than `SchemaVersion`, design tokens, theme controller, hotkey package, settings, onboarding, README.md (explicitly deferred), release workflow, signing, notarization, branch protection (the owner configures it), auto-merge.

## Requirements
- Follow docs/03-code-standards.md. No TODOs, no stubs, no commented-out code, no unrequested abstractions or dependencies.
- Do not add any third-party Swift dependency.
- No hard-coded product name in source beyond the target/module name `PresenterApp` and the places defined in project.yml.
- Strings via `L10n` only. Colors: none hard-coded.
- Generated files (`*.xcodeproj`) must not be committed.
- Edge cases to handle: tool missing, `xcodegen` run twice (idempotent), clean checkout builds, Xcode license not accepted, remote unreachable, SwiftLint/swift-format version differences (record the tool versions in docs/11).

## Acceptance criteria
- [ ] `git log --oneline` on main shows exactly one commit (docs); the bootstrap branch has the six commits above in order.
- [ ] From a clean clone of the branch: `make generate && make verify` passes with zero warnings.
- [ ] The app builds and launches as a menu-bar-only app (no Dock icon); popover shows name, version and a working Quit; strings are localized.
- [ ] `swift test --package-path Packages/ModeKit` and the app test target both pass; test counts reported.
- [ ] `git ls-files` contains no `.xcodeproj`, no `.DS_Store`, no build output.
- [ ] CI workflow passes on the PR (check with `gh pr checks`; if it fails, fix and report).
- [ ] No file over 300 lines; SwiftLint strict passes.

## Test plan
- Automated: the two tests above; `make verify` run from a freshly cloned directory in a temporary location (not inside the working tree) to prove reproducibility.
- Manual QA (execute and report, or give me exact steps if you cannot): launch the built app, confirm menu-bar icon, popover content in English and then with the system language set to Russian (or via `-AppleLanguages "(ru)"` launch argument), Quit works, no Dock icon, no running process after Quit.

## Git instructions
- Follow docs/05-git-workflow.md exactly. Stage files explicitly (never `git add .` or `-A`). Read `git diff --cached` before each commit. Run `make verify` before each commit from step 2 onward. Never `--no-verify`.
- Push the branch and open a PR with `gh pr create`, title `chore: bootstrap repository, tooling and app skeleton`, description per the PR template, including the exact commands you ran and their results. Do not merge.

## Report format
Branch, Commits (hash + subject), Files changed, make verify result with test counts, Manual QA results, CI result, Docs updated, Observed but not done, Unverified, Next step.
