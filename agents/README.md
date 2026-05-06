# agents/

Sub-agent prompt files. Each is a Markdown document with a YAML
frontmatter block (`description`, `name`) and a body that the host (Claude
Code, Cursor, Continue, Copilot Chat, etc.) loads as a system prompt for
delegated tasks.

## What each agent does

| Agent | Trigger phrases | What it does |
|---|---|---|
| `daily-brief.md` | "what was I working on", "daily brief", "standup", "catch me up", "where did I leave off" | Reads the most recent `~/.local/state/session-logs/<date>.md` plus live `gh` state and produces a prioritized standup. Read-only. |
| `pr-author.md` | "open PR", "draft PR", "write commit message", "self-review my branch", "name this branch", "squash for upstream" | Generates upstream-ready titles, commit messages, and PR bodies in a distilled-maintainer voice. Runs a pre-open self-review. Suggests `git`/`gh` commands; does not run them. |
| `pr-reviewer.md` | "review this", "code review", "is this safe to merge", "review mode" | Applies a five-lens methodology with seven distilled techniques. Read-only; produces structured findings with concrete fix snippets. |
| `session-log.md` | end-of-session, "log this session", "wrap up" | Appends a structured entry to `~/.local/state/session-logs/<date>.md` so tomorrow's `daily-brief` has signal. |
| `worktree-setup.md` | any non-trivial editing task, "worktree", "isolate work", "parallel agents" | Enforces "one agent per worktree". Detects collisions and produces the exact `wt` commands to isolate the current task. |

Domain-specific agents (for example, Gatekeeper policy authoring)
live in [examples/agents/](../examples/agents/) — they're shipped as
**templates** to show how to write your own per-repo agent, not as
ready-to-use defaults.

## How agents reference each other

- `pr-reviewer` references `memories/pr-review-techniques.md`.
- `pr-reviewer` (when the diff is in a Kubernetes-org repo) layers in
  `examples/skills/kubernetes-sig-auth-rigor` and `memories/sig-auth-rigor.md`.
- `pr-author` references `skills/distributed-systems-author-style`.
- `daily-brief` consumes the output of `scripts/session-log-compile.sh`.
- `worktree-setup` is the gate every editing agent should call before
  touching files.

## Installing

See [`../INSTALL.md`](../INSTALL.md). For Claude Code the convention is
`~/.claude/agents/<name>.md`; for other hosts, consult the host's docs
for sub-agent prompt locations.

## Editing your own

Keep the YAML frontmatter intact (`description` is what the host uses to
route a request to the agent). Body length: aim for ≤ 200 lines per
agent — beyond that, split into a skill loaded on-demand.
