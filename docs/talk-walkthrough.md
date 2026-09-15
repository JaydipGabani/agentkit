# AI Workflow Walkthrough — talk demo notes

A guided tour of the AI tooling in this repo, presented as six
pillars. Each section names the artifact, gives a demo command, and a
talking point. Open the linked files relative to the repo root as you
go.

> This file was originally written as live-demo notes for a talk
> showcasing one author's setup. The personal paths have been
> rewritten to repo-relative form, but the *narrative voice* — first
> person, "I use this every day" — is intentionally preserved. Read
> it as a worked example of *how* to compose the toolkit, not as a
> normative reference. The reference docs are
> [`../README.md`](../README.md) and [`../INSTALL.md`](../INSTALL.md).

---

## TL;DR

Six interlocking pillars, all custom, all grounded in real engineering practice (not vendor demos):

| Pillar | What it solves | Primary artifact |
|---|---|---|
| 1. Git worktrees | Multiple agents/branches without clobbering | `~/.local/bin/wt` |
| 2. Session logs | "What was I working on yesterday?" | `~/.local/bin/session-log-compile.sh` + systemd timer |
| 3. Daily Brief agent | Standup-style snapshot + GitHub triage | `~/.claude/agents/daily-brief.agent.md` |
| 4. PR review skills | Senior-maintainer-grade code review | `~/.claude/skills/distributed-systems-pr-review/SKILL.md` + `pr-reviewer` agent |
| 5. PR author skills | Upstream-ready commits, branches, descriptions | `~/.claude/skills/distributed-systems-author-style/SKILL.md` + `pr-author` agent |
| 6. Session titles | Human-readable identity across chat windows | `extensions/session-title/` + `scripts/session-title-hook` |

Each is read-only by default, citation-driven, and modular — pick any one without the others.

---

## Pillar 1 — Git worktrees: one agent per worktree

**Problem.** When two agents (or one agent + me) edit the same checkout, they trash each other's in-flight work. Stashing/branching constantly is friction.

**Solution.** A `wt` helper that wraps `git worktree` with conventions: canonical clone stays read-only at `~/code/<org>/<repo>`, all active work happens at `~/worktrees/<repo>/<branch>`. One agent per worktree, full stop.

### Artifacts to open

- [`.local/bin/wt`](../scripts/wt) — 280-line bash helper. Subcommands: `new`, `list`, `rm`, `prune`, `cd`. Read the header comment for the convention.
- [`.claude/agents/worktree-setup.agent.md`](../agents/worktree-setup.agent.md) — agent that enforces the rule. Triggered when starting any non-trivial multi-edit task.

### Demo

```bash
# Show the helper
wt list

# Show how many worktrees gatekeeper has right now
git -C ~/code/open-policy-agent/gatekeeper worktree list | wc -l
# 19 active worktrees on one repo
```

### Talking point

> "I ran into agents stomping on each other in the same checkout exactly once. Now every agent gets its own worktree, declared up-front. The helper makes the cost of starting a new branch ~3 seconds, so there's no incentive to cheat the rule."

---

## Pillar 2 — Session logs: deterministic daily snapshots

**Problem.** End of day: 9 chat sessions, 5 worktrees touched, 38-message-deep thread mid-question. Tomorrow morning: total amnesia. VS Code's chat history UI is per-session and gives me no cross-session view.

**Solution.** A systemd user timer that runs once a day and walks `~/.vscode-server/data/User/workspaceStorage/*/GitHub.copilot-chat/transcripts/*.jsonl`, plus every git repo + worktree, and emits a markdown digest to `~/.local/state/session-logs/<YYYY-MM-DD>.md`.

### Artifacts to open

- [`.local/bin/session-log-compile.sh`](../scripts/session-log-compile.sh) — the generator. ~170 lines of bash + jq. Walk through the three sections: chat-transcript scan, git-activity scan, output composition.
- [`.config/systemd/user/session-log-compile.service`](../systemd/session-log-compile.service) — oneshot service.
- [`.config/systemd/user/session-log-compile.timer`](../systemd/session-log-compile.timer) — fires at 17:00 PT daily.
- [`session-logs/2026-05-05.md`](~/.local/state/session-logs/2026-05-05.md) — yesterday's actual log. Show the new per-session schema.
- [`session-logs/2026-05-06.md`](~/.local/state/session-logs/2026-05-06.md) — today's log.

### What's in each session block

```
- **`533fe3f0`** in `gatekeeper` (ws `61def0c1-2`) — 38 user msg(s)
  - first: <opening prompt — the intent>
  - last:  <most recent prompt — where I stopped, often mid-question>
  - last edit: <the last file an edit tool touched>
  - transcript: <full path to .jsonl, so the brief can drill in>
```

### Demo

```bash
# Fire the systemd service on demand
systemctl --user start session-log-compile.service

# Show the most recent log
ls -t ~/.local/state/session-logs/*.md | head -3
cat ~/.local/state/session-logs/$(date +%Y-%m-%d).md
```

### Coverage scope

- **All VS Code windows** on this host (including re-opened workspaces — discriminated by `-1`/`-2` suffixes).
- **All worktrees** of repos in the hardcoded `REPOS=(...)` list. Currently 7 repos, 19+ worktrees on gatekeeper alone.
- **Filter:** mtime within last 24h. Stale chats drop off automatically.

### Talking point

> "The killer feature isn't the stats — it's the *last user message* per session. That's the strongest signal of where I left off, and it lets the brief say `you stopped mid-question on \"can you run stages to confirm?\"` instead of a vague \"you were in gatekeeper\". The transcript path lets the brief drill into the .jsonl if it needs more context."

---

## Pillar 3 — Daily Brief agent: standup + triage in one pull

**Problem.** Even with good session logs, GitHub state is live and not in the log. PRs got reviewed overnight, CI flipped, notifications piled up. I want a single 40-line view that says *do this next*.

**Solution.** A read-only Claude/Copilot agent that combines the compiled session log with `gh notifications`, `gh search prs`, `gh search issues`, and classifies everything into priority lanes.

### Artifacts to open

- [`.claude/agents/daily-brief.agent.md`](../agents/daily-brief.agent.md) — the agent prompt. Walk through the constraints (read-only, citation-required, 40-line cap), the 5-step approach, and the lane taxonomy.

### The lane taxonomy

```
[CHANGES]  reviewer requested changes / unresolved comments newer than my push
[CI-FAIL]  failing required check on my PR
[CONFLICT] mergeable=CONFLICTING
[REVIEW]   review requested from me
[READY]    approved + mergeable + green
[WIP]      local branch with uncommitted/unpushed work, no PR yet
[DRAFT]    my draft PR
[STALE]    PR untouched >5 days
```

Order: CHANGES → CI-FAIL → CONFLICT → REVIEW → READY → WIP → DRAFT → STALE → issues.

### Demo

In a fresh chat: type `daily brief` or `where did I leave off` — the agent loads.

It will:
1. `ls -t ~/.local/state/session-logs/*.md | head -3` and read the freshest.
2. Run the four `gh` queries in parallel.
3. Emit ~40 lines, one section per lane, citing PR numbers and SHAs.

### Talking point

> "The brief is read-only by design. It never edits files, never pushes, never even refreshes git unless the log is older than 2h. Trust comes from the citation rule: every bullet has a concrete source — commit SHA, PR number, file path — so I can verify any line in 2 seconds."

---

## Pillar 4 — PR review skills: senior-maintainer-grade reviews

**Problem.** Default LLM review = surface-level style nits. I want the kind of review where the reviewer has internalized the codebase and catches lifecycle bugs, version-skew traps, and missing tests.

**Solution.** A skill distilled from mining real review comments by a senior maintainer on the OPA repos, then layered: user-scoped general skill + repo-scoped specialization skill + agent that picks the right one.

### Architecture

```
General (any distributed-systems repo)
└── ~/.claude/skills/distributed-systems-pr-review/SKILL.md
    Five-lens method + 7 review techniques (the distilled senior-maintainer moves)

Repo-specialized
├── gatekeeper/.github/skills/gatekeeper-correctness-pr-review/SKILL.md
├── kubernetes/.github/skills/kubernetes-correctness-pr-review/SKILL.md
└── …

Routing
├── gatekeeper/.github/instructions/gatekeeper-skill-routing.instructions.md
└── kubernetes/.github/instructions/kubernetes-skill-routing.instructions.md

Agent that loads the right one
└── ~/.claude/agents/pr-reviewer.agent.md
```

### The seven moves (distilled from the mining corpus)

1. **Trace every edited block through the 5 lenses**: invariants, consistency, state cleanup, input safety, silent-failure blast radius.
2. **Check parallel code paths**: if you changed one place, find the others doing the same thing.
3. **Cross-reference platform limits** (K8s name 253, label 63, etc.).
4. **Read wrapper-type internals** — don't assume `source.Channel` and a raw chan have the same semantics.
5. **Verify "pre-existing behavior"** by reading actual old code, not pattern-matching.
6. **Check nil/zero on every pointer parameter** at API boundaries.
7. **Confirm error paths log or return** — never silently swallow.

### Artifacts to open

- [`distributed-systems-pr-review/SKILL.md`](../skills/distributed-systems-pr-review/SKILL.md) — top-level skill.
- [`gatekeeper-correctness-pr-review/SKILL.md`](https://github.com/open-policy-agent/gatekeeper/.github/skills/gatekeeper-correctness-pr-review/SKILL.md) — repo-specialized.
- [`kubernetes-correctness-pr-review/SKILL.md`](https://github.com/kubernetes/kubernetes/.github/skills/kubernetes-correctness-pr-review/SKILL.md) — same pattern, different repo.
- [`pr-reviewer.agent.md`](../agents/pr-reviewer.agent.md) — the agent that orchestrates.
- [`/memories/code-review-methodology.md`](command:claude.openMemory?code-review-methodology) — persistent reminder.
- [`/memories/pr-review-techniques.md`](command:claude.openMemory?pr-review-techniques) — the 7 moves.

### Mining corpus (the source of truth)

The raw mining corpus (~8.6 MB of public review comments + 188 distilled
utterances + the intermediate `substantive.json` filter output) lives
outside this repo and is not redistributed. The corpus is the *input*
to the mining; the *output* is the abstracted ruleset checked into:

- [`memories/pr-review-techniques.md`](../memories/pr-review-techniques.md) — the seven moves + voice cues + repo conventions + pre-merge checklist.
- [`skills/distributed-systems-pr-review/SKILL.md`](../skills/distributed-systems-pr-review/SKILL.md) — the agent-facing rendering.

If you want to do similar mining on a maintainer of your choice, use
`gh search prs --reviewed-by=<handle>` + `gh pr view --json reviews,comments`,
then distill into your own ruleset. Keep the corpus private; publish
only the abstraction.

### Demo

In a fresh chat, with a real PR open: type `review this PR` and pass the URL. Or in a worktree: `review my staged changes`.

The agent will:
1. Detect the repo, load the right specialized skill.
2. Walk every edited block through the 5 lenses.
3. Emit a structured "Findings" section with concrete fix snippets, no style nits.

### Talking point

> "The mining was the unlock. I didn't write these techniques — I extracted them from 188 real comments by someone who's been reviewing this codebase for years. The skill is just the distilled procedure. The agent and the specialized skills are scaffolding that makes it loadable."

---

## Pillar 5 — PR author skills: upstream-ready output

**Problem.** Default LLM commit messages and PR descriptions read like a robot wrote them. They get rejected by maintainers or burn reviewer attention on rewording.

**Solution.** Mirror of pillar 4, but for the *authoring* side. Mined the same maintainer's own PR titles, commit messages, and PR bodies (38 upstream PRs after dedup), distilled into a skill that produces output indistinguishable from the source.

### Artifacts to open

- [`distributed-systems-author-style/SKILL.md`](../skills/distributed-systems-author-style/SKILL.md) — 152 lines: branch naming, commit subject conventions, PR title format, body structure.
- [`pr-author.agent.md`](../agents/pr-author.agent.md) — the agent. 122 lines.
- The 50 authored PRs and the distilled `author_patterns.txt` that
  drove the skill are part of the same private mining corpus described
  above and are not redistributed.

### What it produces

- Branch names: `fix/<short-noun>` / `feat/<short-noun>` / `cherry-pick/<thing>-<release>` — never `copilot-foo-bar-baz-12345`.
- Commit subjects: `<type>(<scope>): <imperative verb>` capped at 72 chars.
- PR titles: same convention, no emoji, no "PR:" prefix.
- PR body: Context → Change → Tests → Risk, in that order, ≤30 lines.
- Pre-open self-review using the 5-lens method from pillar 4.

### Demo

In a fresh chat with a worktree that has staged changes: `open PR for this branch`.

The agent:
1. Inspects the diff.
2. Runs a pre-open self-review (calls into pillar 4's skill).
3. Generates branch name, commit message, PR title, PR body.
4. Suggests `git`/`gh` commands but does NOT run them. Read-only by default.

### Talking point

> "Same maintainer, same mining technique, opposite direction. Pillar 4 catches what reviewers would say; pillar 5 makes my output match what they'd write themselves. They share the 5-lens method — author uses it as a self-review before opening, reviewer uses it on incoming PRs."

---

## Pillar 6 — Human-readable session titles

**Problem.** Ten chat tabs named from fragments of their opening prompt are not
meaningful session identity, especially when several sessions concern the same
PR across local chat and the Agents Window.

**Solution.** A user-scoped `UserPromptSubmit` hook forwards the prompt to a
small workspace-host extension. When the prompt contains a GitHub PR or Issue
link, the extension fetches that item's title with `gh` and applies it directly:

```text
Prompt: Review https://github.com/open-policy-agent/gatekeeper/pull/4816
Title:  Add per-constraint VAP generation
```

Prompts without a full PR or Issue link are ignored. Bridge descriptors are
private and workspace-scoped; focused-window metadata disambiguates duplicate
workspaces. Hook `cwd` only routes the event to a window.

### Artifacts to open

- [`extensions/session-title/`](../extensions/session-title/) — extension,
  provider adapters, naming core, and tests.
- [`scripts/session-title-hook`](../scripts/session-title-hook) — hook bridge
  client.
- [`scripts/install-session-titles.sh`](../scripts/install-session-titles.sh) —
  one-command local/remote host installer.

### Demo

Open a fresh local chat and paste a GitHub PR URL. The title changes to the exact
PR title. A prompt with only `PR #4816` does nothing. Copilot CLI sessions use the
same linked-title rule and can be targeted directly.

### Talking point

> "There is no naming heuristic: paste a PR or Issue link and the chat gets that
> item's title. Otherwise, the extension leaves the title alone."

---

## How the pieces compose

```
Morning:
  open VS Code
  → type "daily brief" in fresh chat
  → Daily Brief agent reads yesterday's session log + GitHub state
    → tells me: "resume the policy worktree, last edit
      pkg/controller/reconcile.go, next step is to rerun focused tests"
  → I open that worktree (one already exists per branch — pillar 1)

Mid-day:
  ad-hoc work happens across worktrees, multiple chat sessions
  → pillar 6 gives each session a semantic, collision-free title
  systemd timer at 17:00 PT compiles today's session log

Reviewing:
  PR review request comes in
  → @pr-reviewer agent
  → loads distributed-systems-pr-review skill + repo-specialized skill
  → applies 5 lenses + 7 moves
  → emits findings with citations

Authoring:
  finished a feature in a worktree
  → @pr-author agent
  → self-reviews using pillar 4's lenses
  → generates branch name, commit, title, body in maintainer voice
  → I run the suggested gh pr create

End of day:
  next day's brief picks up the deltas. Loop closes.
```

---

## Repo-scoped engineering principles & routing

The skills don't fire automatically — they're routed by per-repo instruction files:

- [`gatekeeper-engineering-principles.instructions.md`](https://github.com/open-policy-agent/gatekeeper/.github/instructions/gatekeeper-engineering-principles.instructions.md) — root-cause discipline, lifecycle safety, test depth.
- [`gatekeeper-skill-routing.instructions.md`](https://github.com/open-policy-agent/gatekeeper/.github/instructions/gatekeeper-skill-routing.instructions.md) — picks which skill to load for each task type.
- [`kubernetes-engineering-principles.instructions.md`](https://github.com/kubernetes/kubernetes/.github/instructions/kubernetes-engineering-principles.instructions.md) — same shape, K8s-specific rules.
- [`kubernetes-skill-routing.instructions.md`](https://github.com/kubernetes/kubernetes/.github/instructions/kubernetes-skill-routing.instructions.md) — K8s routing.

Plus repo-level `AGENTS.md` files for codebase context (gatekeeper, kubernetes, gatekeeper-library, NVIDIA/aicr).

---

## Memory layer (the glue)

```
/memories/
├── code-review-methodology.md   # 5-lens method, auto-loaded every chat
├── pr-review-techniques.md      # the 7 moves
├── preferences.md               # "user prefers brief responses"
├── tool-use.md                  # "execution_subagent: explicitly say not to edit"
├── worktree-workflow.md         # the one-agent-per-worktree rule
├── session/                     # per-conversation scratch (auto-cleared)
└── repo/
    └── gatekeeper-validation.md # repo-scoped facts
```

First 200 lines of `/memories/*.md` (top level) are loaded into every conversation's context automatically. That's how the principles persist.

---

## Suggested talk structure (15 min)

1. **30s — the pain** (multi-window VS Code chaos screenshot).
2. **2 min — pillar 1 (worktrees)**: live `wt new`, show 19 active worktrees.
3. **3 min — pillar 2+3 (session log → daily brief)**: open today's session log, read one entry, then `daily brief` in fresh chat. The "resume mid-question" moment is the most visceral demo.
4. **3 min — pillar 4 (review)**: pull a real PR, run `@pr-reviewer`, show structured findings cite the same patterns as the mining corpus.
5. **2 min — pillar 5 (author)**: stage a small change, run `@pr-author`, show the output side by side with a real maintainer PR.
6. **1 min — pillar 6 (titles)**: open two sessions for one PR and show their semantic ordinal titles.
7. **1.5 min — composition**: walk the morning → mid-day → review → author → next-day loop.
8. **1 min — what's distilled vs. what's vendor**: emphasize that the techniques came from mining real engineer behavior (hundreds of reviewer comments and dozens of authored PRs), not from prompt engineering.

---

## Common questions to anticipate

| Q | A |
|---|---|
| Does this work in Cursor/Continue/X? | The agents and skills are markdown — portable. The wrappers (worktree helper, systemd timer) are bash. The mining is JSON. |
| What's specific to Copilot/Claude? | Just the agent invocation syntax (`@agent-name`) and the memory tool API. Everything else is content. |
| Why mining instead of prompting? | Because the techniques aren't in the LLM's training set as a labeled "senior maintainer review method". They had to be extracted. The skill is the distillation step. |
| Read-only? Really? | Daily Brief and PR Reviewer are strictly read-only. PR Author suggests commands but doesn't run them. Worktree Setup creates worktrees but only with explicit user confirmation. Session-log compile only writes to `~/.local/state/session-logs/`. |
| What does this cost in tokens? | Session log compile is 0 tokens (deterministic bash). Daily Brief is ~3-5K input tokens (log + GitHub state). Reviewer/author scale with diff size. |
| What if I'm offline? | Session log + worktree helper still work. Daily Brief degrades to "session log only" without GitHub state. |

---

## File index (for live demo)

| Pillar | File | Purpose |
|---|---|---|
| 1 | `~/.local/bin/wt` | Worktree helper |
| 1 | `~/.claude/agents/worktree-setup.agent.md` | Worktree agent |
| 2 | `~/.local/bin/session-log-compile.sh` | Compiler |
| 2 | `~/.config/systemd/user/session-log-compile.{service,timer}` | Schedule |
| 2 | `~/.local/state/session-logs/2026-05-06.md` | Today's log |
| 3 | `~/.claude/agents/daily-brief.agent.md` | Brief agent |
| 4 | `~/.claude/skills/distributed-systems-pr-review/SKILL.md` | General review skill |
| 4 | `gatekeeper/.github/skills/gatekeeper-correctness-pr-review/SKILL.md` | Repo-specialized |
| 4 | `kubernetes/.github/skills/kubernetes-correctness-pr-review/SKILL.md` | Repo-specialized |
| 4 | `~/.claude/agents/pr-reviewer.agent.md` | Review agent |
| 5 | `~/.claude/skills/distributed-systems-author-style/SKILL.md` | Author skill |
| 5 | `~/.claude/agents/pr-author.agent.md` | Author agent |
| 6 | `extensions/session-title/` | Semantic title extension and tests |
| 6 | `~/.local/bin/agentkit-session-title-hook` | User prompt hook bridge |
| 4+5 | (mining corpus, kept private) | The corpus the skills came from. Abstracted ruleset is in `memories/pr-review-techniques.md`. |
| Glue | `/memories/*.md` | Auto-loaded persistent notes |
| Glue | `gatekeeper/.github/instructions/*.instructions.md` | Repo skill routing |

---

## Open questions for the talk

1. Audience: peer engineers, leadership, or ML/AI-curious general?
2. Live demo or recorded? Live is more visceral; recorded protects against gh API hiccups.
3. Which pillar do you want to deep-dive? (One pillar in 15 min works better than skimming all 6.)
4. Do you want to show the mining process itself (the GraphQL → JSON → SKILL.md pipeline)? That's a great "show your work" moment but adds 5 min.
5. Companion artifact (gist? blog post? GitHub repo with templates)? Useful for follow-ups.
