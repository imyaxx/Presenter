# Claude Code protocol

How work is requested and executed so that every session, including a fresh one with no memory, produces exactly what was asked.

## Roles

- The user directs and approves.
- A planning assistant (claude.ai) writes task prompts and maintains docs.
- Claude Code executes tasks inside the repository on the user's Mac.

## Session rules

1. Start with the protocol in `CLAUDE.md`: read `docs/STATUS.md`, `docs/README.md`, and relevant docs.
2. One prompt = one branch = one reviewable unit of work. Do not bundle unrelated work.
3. Scope is fixed by the prompt. Anything outside it is listed under "Observed but not done" in the final report, not implemented.
4. Prefer small verified steps: implement, run the relevant tests, then continue. Run `make verify` before committing.
5. Ask at most one question, and only when blocked. Otherwise choose the conservative option, record it, and continue.
6. Never claim success without evidence. Quote the command and its result.
7. Do not commit until: `make verify` is green, the manual QA items required by the prompt are executed (or explicitly handed to the user with exact steps), and `git diff --cached` has been read.
8. Push the branch and open a PR only when the prompt says so. Never merge. The user merges.

## Prompt structure

Every prompt follows `docs/prompts/TEMPLATE.md`. Mandatory sections: Role, Context to read, Objective, Scope, Out of scope, Requirements, Acceptance criteria, Test plan, Git instructions, Report format. Prompts are in English and detailed enough that the executor makes no product decisions.

## Final report format (from Claude Code)

```
Branch: <name>
Commits: <hash subject> (one per line)
Files changed: <count>, key files: <list>
make verify: <pass/fail, test counts>
Manual QA: <items executed and results, or items for the user with exact steps>
Docs updated: <list>
Observed but not done: <list>
Unverified: <list>
Next step: <one line>
```

## Handoff discipline

At the end of each session, `docs/STATUS.md` must let a fresh session continue without conversation history: milestone, branch state, what is merged, what is next, open questions, and the verified or unverified status of platform facts.

## When docs and prompt conflict

Stop. Report the conflict and the minimal fix. Do not guess.
