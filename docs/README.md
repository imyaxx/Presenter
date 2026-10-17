# Documentation index

Single source of truth for the project. A new Claude Code session must be able to continue the work using only this folder and the code.

| File | Purpose | Update when |
|---|---|---|
| `STATUS.md` | Current milestone, next step, open questions, session log | Every session |
| `00-product-brief.md` | What we build, for whom, scope and non-goals, user flows | Scope changes |
| `01-architecture.md` | Layers, domain model, state machine, persistence, error policy | Architecture changes |
| `02-project-structure.md` | Folder tree, dependency rules, naming of files and targets | Structure changes |
| `03-code-standards.md` | Swift conventions, concurrency, errors, logging, limits | Rules change |
| `04-design-system.md` | Visual direction, tokens, theming, components, localization | Design changes |
| `05-git-workflow.md` | Branching, commits, PRs, protection, release flow | Process changes |
| `06-testing.md` | Test pyramid, fakes, coverage targets, manual QA checklists | Test strategy changes |
| `07-macos-integration.md` | Per-action system mechanics, verified vs unverified facts, spike log | Every spike or platform finding |
| `08-roadmap.md` | Milestones M0 to M5 with acceptance criteria | Milestone scope changes |
| `09-decisions.md` | Architecture decision records and open decisions | Every decision |
| `10-claude-code-protocol.md` | How prompts are written, how sessions start and end | Process changes |
| `11-development-setup.md` | Tools and versions, first run, daily commands, troubleshooting | Tooling changes or a new setup problem |
| `prompts/TEMPLATE.md` | Prompt template used for every task | Template changes |

Rules for docs:

- Written in English, plain, no marketing language.
- Dates are absolute (`2026-10-17`), never "recently" or "soon".
- State what is known; mark what is unverified with the literal word `UNVERIFIED`.
- A doc that disagrees with the code is a bug. Fix it in the same PR as the code change.
