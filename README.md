# agentkit

Reusable agents, skills, scripts, and configuration that turn an
LLM-assisted IDE into a **multi-repo, multi-agent dev workflow** — with
durable session memory, daily standup briefs, parallel-agent isolation,
and PR review/author voices distilled from senior maintainers.

This is not a framework or an extension. It's a small, hostable set of
markdown prompts and POSIX shell scripts that you drop into your
existing setup (Claude Code, Cursor, Continue, Copilot Chat — anything
that reads system prompts).

> If you've ever ended a day with nine open chat sessions across five
> worktrees and three repos, then come back the next morning unsure
> what you were doing — this toolkit is the answer to "fix that."

## What's inside

| Pillar | Where | What it solves |
|---|---|---|
| **1. Worktree isolation** | [`scripts/wt`](scripts/wt) + [`agents/worktree-setup.md`](agents/worktree-setup.md) + [`memories/worktree-workflow.md`](memories/worktree-workflow.md) | Two agents on one repo never write to the same working tree. The agent gates editing tasks behind a worktree decision; `wt` is the helper. |
| **2. Daily session digest** | [`scripts/session-log-compile.sh`](scripts/session-log-compile.sh) + [`systemd/`](systemd/) | A nightly compile of every chat transcript and git activity into a single Markdown file under `~/.local/state/session-logs/`. Per-session: UID, workspace hash, primary repo, msg count, first/last prompt, last edit. |
| **3. Daily Brief agent** | [`agents/daily-brief.md`](agents/daily-brief.md) | Reads the latest digest + live `gh` state and produces a prioritized standup: CHANGES → CI-FAIL → CONFLICT → REVIEW → READY → WIP → DRAFT → STALE. Read-only. |
| **4. PR Reviewer voice** | [`agents/pr-reviewer.md`](agents/pr-reviewer.md) + [`skills/distributed-systems-pr-review/`](skills/distributed-systems-pr-review/) + [`memories/pr-review-techniques.md`](memories/pr-review-techniques.md) | Seven concrete review moves (trace the flow, future fragility, lock scope, test-as-no-op, silent-fallback hazard, error formatting, platform limits) distilled from senior maintainer history. |
| **5. PR Author voice** | [`agents/pr-author.md`](agents/pr-author.md) + [`skills/distributed-systems-author-style/`](skills/distributed-systems-author-style/) | Upstream-ready titles, commit messages, and PR bodies in a distilled-maintainer style; pre-open self-review. Suggests `git`/`gh` commands; doesn't run them. |

## Quick start

```sh
git clone https://github.com/jaydipgabani/agentkit.git
cd agentkit
# Read the install steps for your host:
$EDITOR INSTALL.md
```

The TL;DR for Claude Code on Linux:

```sh
# Agents and skills
mkdir -p ~/.claude/agents ~/.claude/skills
cp agents/*.md          ~/.claude/agents/
cp -r skills/*/         ~/.claude/skills/

# Scripts
install -Dm755 scripts/wt                    ~/.local/bin/wt
install -Dm755 scripts/session-log-compile.sh ~/.local/bin/session-log-compile.sh

# Repo list (edit before first run!)
mkdir -p ~/.config/agentkit
cp examples/repos.txt ~/.config/agentkit/repos.txt
$EDITOR ~/.config/agentkit/repos.txt

# Daily compile via systemd
mkdir -p ~/.config/systemd/user
install -m644 systemd/*.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now session-log-compile.timer

# Smoke test
~/.local/bin/wt list
~/.local/bin/session-log-compile.sh
ls ~/.local/state/session-logs/
```

Full host-specific instructions (Claude Code, Cursor, Continue, Codex,
non-systemd setups) in [`INSTALL.md`](INSTALL.md).

## Repo layout

```
agentkit/
├─ agents/                     # general-purpose sub-agent prompts
│  ├─ daily-brief.md
│  ├─ pr-author.md
│  ├─ pr-reviewer.md
│  ├─ session-log.md
│  └─ worktree-setup.md
├─ skills/                     # general-purpose on-demand skill bundles
│  ├─ distributed-systems-pr-review/
│  ├─ distributed-systems-author-style/
│  └─ distributed-systems-security-hardening/
├─ scripts/
│  ├─ wt                       # git-worktree helper
│  └─ session-log-compile.sh   # daily digest compiler
├─ systemd/
│  ├─ session-log-compile.service
│  └─ session-log-compile.timer
├─ memories/                   # auto-loaded context (user-tier)
│  ├─ code-review-methodology.md
│  ├─ pr-review-techniques.md
│  ├─ sig-auth-rigor.md
│  ├─ worktree-workflow.md
│  └─ tool-use.md
├─ docs/
│  └─ talk-walkthrough.md      # 5-pillar live demo doc
├─ examples/                   # domain-specific templates
│  ├─ agents/
│  │  └─ gatekeeper-policy-author.md
│  ├─ skills/
│  │  └─ kubernetes-sig-auth-rigor/
│  └─ repos.txt
├─ INSTALL.md
├─ LICENSE
└─ README.md
```

## Reuse model — what's portable, what isn't

| Layer | Portable? | Notes |
|---|---|---|
| **Agent prompts** (`agents/*.md`) | Yes — pure Markdown + YAML frontmatter. | Path conventions are noted in the prompts; rewrite them for your host. |
| **Skills** (`skills/*/SKILL.md`) | Yes — pure Markdown. | Some hosts call these "rules" or "instructions"; the content is the same. |
| **Memories** (`memories/*.md`) | Yes, but the *install path* varies by host. | They're meant to be auto-loaded into every turn, not lazily fetched. |
| **`scripts/wt`** | Linux/macOS Bash. | Pure `git`/`bash`; no extra deps. |
| **`scripts/session-log-compile.sh`** | Linux/macOS Bash. Requires `jq`, `find`, `git`. Reads VS Code chat transcripts under `~/.vscode-server/data/User/workspaceStorage/`. | The transcript path is VS Code-specific. For other editors, point the script at the equivalent transcript directory. |
| **`systemd/`** | Linux with systemd user instance. | Provided as a starting point; macOS users want `launchd`, others want cron. The `systemd/README.md` covers conversions. |

## Compatibility

- **Editors**: VS Code (with Copilot Chat or any chat extension that
  writes JSONL transcripts under `workspaceStorage/`). The session-log
  compiler is the only piece coupled to VS Code's storage layout;
  agents/skills are editor-agnostic.
- **LLM hosts**: Claude Code is the primary target (sub-agents +
  skills + memory tool match cleanly). The same Markdown works as
  Cursor "rules", Continue "config", or Copilot Chat "custom
  instructions" with light adaptation.
- **OS**: Linux (primary) and macOS for the scripts. The Markdown is
  OS-agnostic.

## Provenance and credit

The PR review and author skills under `skills/` and the corresponding
notes under `memories/` are **abstracted patterns** distilled from the
public PR-review and commenting history of senior open-source
maintainers in the Kubernetes / OPA / Azure ecosystems. The raw mining
corpora — which contain personally-attributable phrasing and timing
data — are **not redistributed** in this repo. If you do similar
mining yourself, treat the corpus as private and publish only the
abstracted ruleset.

## Talk / walkthrough

[`docs/talk-walkthrough.md`](docs/talk-walkthrough.md) is a 5-pillar
live demo doc — the same one used to walk teammates through the
toolkit. Open the linked artifacts as you go.

## Contributing

This is a personal toolkit shared for reuse, not a maintained product.
PRs that improve portability (more hosts, better fallbacks, fewer
hard-coded paths) are welcome. Domain-specific agents are best kept
in your own fork.

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for provenance and
attribution requirements when redistributing.
