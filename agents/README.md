# agents/

Sub-agent prompt files. Each is a Markdown document with a YAML
frontmatter block (`description`, `name`) and a body that the host (Claude
Code, Cursor, Continue, Copilot Chat, etc.) loads as a system prompt for
delegated tasks.

## What each agent does

| Agent | Trigger phrases | What it does |
|---|---|---|
| `daily-brief.agent.md` | "what was I working on", "daily brief", "standup" | Produces a cited, prioritized cross-repo brief. |
| `dependabot-round-robin.agent.md` | "manage Dependabot PRs" | Drains four OPA repository queues with bounded retries and explicit merges. |
| `gatekeeper-policy-author.agent.md` | "write a Gatekeeper policy", "add CEL" | Authors dual-engine policies with generated manifests and test coverage. |
| `pr-author.agent.md` | "open PR", "draft PR", "write commit message" | Produces upstream-ready branch, commit, and PR artifacts. |
| `pr-reviewer.agent.md` | "review this", "code review", "is this safe to merge" | Applies full-repository review methodology, invokes autoreview once when appropriate, and verifies the final findings. |
| `session-log.agent.md` | "log this session", "wrap up" | Appends a compact handoff for the next brief. |
| `worktree-setup.agent.md` | any non-trivial editing task | Enforces one agent per worktree before edits begin. |

## How agents reference each other

- `pr-reviewer` references `memories/pr-review-techniques.md`.
- `pr-reviewer` is the sole review orchestrator; `skills/autoreview` owns external model isolation and structured review execution.
- `pr-reviewer` (when the diff is in a Kubernetes-org repo) layers in
  `skills/kubernetes-sig-auth-rigor` and `memories/sig-auth-rigor.md`.
- `pr-author` references `skills/distributed-systems-author-style`.
- `daily-brief` consumes the output of `scripts/session-log-compile.sh`.
- `worktree-setup` is the gate every editing agent should call before
  touching files.

## Installing

See [`../INSTALL.md`](../INSTALL.md). VS Code uses
`.github/agents/<name>.agent.md` at workspace scope. Claude Code can load
the same files from `~/.claude/agents/`.

## Editing your own

Keep the YAML frontmatter intact (`description` is what the host uses to
route a request to the agent). Body length: aim for ≤ 200 lines per
agent — beyond that, split into a skill loaded on-demand.
