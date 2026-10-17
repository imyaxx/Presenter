# Git workflow

Trunk-based development with short-lived branches. `main` is always releasable.

## Branches

- `main`: protected. No direct pushes. Only squash-merged PRs with green CI.
- Working branches, one per unit of work, created from fresh `main`:
  `feat/<scope>-<short-description>`, `fix/...`, `refactor/...`, `chore/...`, `docs/...`, `test/...`, `ci/...`.
  Lowercase, hyphenated, at most 50 characters. Example: `feat/session-crash-recovery`.
- Branch lifetime: days, not weeks. Rebase on `main` before opening the PR if `main` moved.
- Delete the branch after merge.

## Commits

Conventional Commits, imperative mood, subject at most 72 characters, no trailing period.

```
<type>(<scope>): <subject>

<body: why, not what; wrap at 72; optional>
```

Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`, `revert`.
Scopes: `session`, `dock`, `menubar`, `icons`, `apps`, `wallpaper`, `hotkey`, `theme`, `l10n`, `settings`, `onboarding`, `hud`, `platform`, `build`, `ci`, `docs`.

Rules:

- Atomic: one logical change per commit. Tests for a change live in the same commit as the change.
- Every commit on a working branch builds and passes tests.
- Never `git add .` or `git add -A`. Stage explicit paths. Run `git diff --cached` and read it before every commit.
- Never commit secrets, certificates, provisioning profiles, `.env`, `.xcodeproj`, `DerivedData`, `.DS_Store`.
- Never `--no-verify`. If a hook fails, fix the cause.
- Never amend or rebase commits that are already pushed to a shared branch.

## Pull requests

- One PR = one feature or fix, small enough to review in one sitting.
- Title is the Conventional Commit subject (it becomes the squash commit).
- Description: what and why, how it was tested (commands run and results; manual QA checklist items ticked), screenshots for UI in Light and Dark, risks, docs updated.
- Merge method: **squash only**. The squash commit message is the PR title plus a body that summarizes why.
- Required checks: `make verify` equivalent in CI (lint, format check, build, tests).

## Required GitHub settings (configure once, repository owner)

- Default branch `main`. Branch protection: require PR, require status checks to pass, require branches to be up to date, disallow force pushes and deletion, require linear history.
- Merge options: squash merging only; auto-delete head branches.

## Local gate before every commit and push

1. `make verify` passes.
2. Manual QA checklist for the touched feature (`docs/06-testing.md`) executed and noted.
3. `git status` is clean except for intended files; `git diff --cached` reviewed.
4. `docs/STATUS.md` and any affected docs updated in the same branch.

## Releases

Tag `vMAJOR.MINOR.PATCH` on `main` (semantic versioning). Changelog is generated from Conventional Commits. A release workflow builds, optionally signs and notarizes (when credentials exist), zips, and attaches the artifact to a GitHub Release. Homebrew cask is updated in a separate tap repository. Details in M5.

## Hygiene commands (non-destructive)

```
git fetch origin --prune
git switch main && git pull --ff-only
git switch -c feat/<scope>-<description>
git status
git diff --cached
```

Destructive commands (`reset --hard`, `clean -fd`, `push --force`, branch deletion with unmerged work) require explicit user confirmation first.
