# Worktree Workflow

Canonical repos (your primary clone of each repo) are the **shared shelf** — read, fetch, do not edit during multi-agent work.

Editable, branch-scoped work goes to `~/worktrees/<repo>/<branch>` via the `wt` helper (installed at `~/.local/bin/wt`).

## Decision rule (apply at task start)

- Read-only on default branch → canonical is fine.
- Any branch other than default, OR risk of parallel agents → use `wt`.
- Already in `~/worktrees/...` → proceed.

## Commands

- `wt new <branch> [base]` — create/attach. If branch exists locally or on origin, attaches. Else creates from `origin/<default>` or `[base]`.
- `cd "$(wt cd <branch>)"` — jump to existing worktree.
- `wt status` — dirty + ahead/behind across all worktrees of current repo.
- `wt rm [--force] <branch>` — refuses on dirty/unpushed.
- `wt list`, `wt prune`, `wt root`.

## Invariants

- Never `git checkout` a different branch in the canonical clone for active work.
- Never push from the canonical clone for branch work that has a worktree.
- Reuse, don't recreate — `wt new` is idempotent on existing worktrees.

Agent definition: `agents/worktree-setup.md`.

**Routing is intent-based, not phrase-based.** Invoke `Worktree Setup` as a sub-agent BEFORE editing or running `wt` yourself whenever:
- The user says "lets start work on <issue/PR url>", "implement X", "fix this bug", "add Y", "pick up #NNNN" — anything that implies editing.
- The current branch in any of the workspace repos is not the default branch and the user is asking for changes.
- Multiple agents/sessions could touch the same repo.

Literal trigger phrases ("worktree", "isolate work", "parallel agents", "before I start editing") are a strict subset — do not gate on them.

Do NOT shortcut by running `wt new` directly; the agent does collision detection (existing worktrees, dirty siblings, wrong base ref) that a raw `wt new` skips.
