# agentkit

Reusable agents, skills, scripts, and configuration that turn an
LLM-assisted IDE into a **multi-repo, multi-agent dev workflow** — with
durable session memory, daily standup briefs, parallel-agent isolation,
and PR review/author voices distilled from senior maintainers.

This is not a framework. It is a small, hostable set of Markdown prompts,
supporting scripts, and one optional VS Code extension that you drop into your
existing setup (Claude Code, Cursor, Continue, Copilot Chat — anything that
reads system prompts).

> If you've ever ended a day with nine open chat sessions across five
> worktrees and three repos, then come back the next morning unsure
> what you were doing — this toolkit is the answer to "fix that."

## What's inside

| Pillar | Where | What it solves |
|---|---|---|
| **1. Worktree isolation** | [`scripts/wt`](scripts/wt) + [`agents/worktree-setup.agent.md`](agents/worktree-setup.agent.md) + [`memories/worktree-workflow.md`](memories/worktree-workflow.md) | Two agents on one repo never write to the same working tree. The agent gates editing tasks behind a worktree decision; `wt` is the helper. |
| **2. Daily session digest** | [`scripts/session-log-compile.sh`](scripts/session-log-compile.sh) + [`systemd/`](systemd/) | A nightly compile of every chat transcript and git activity into a single Markdown file under `~/.local/state/session-logs/`. Per-session: UID, workspace hash, primary repo, msg count, first/last prompt, last edit. |
| **3. Daily Brief agent** | [`agents/daily-brief.agent.md`](agents/daily-brief.agent.md) | Reads the latest digest + live `gh` state and produces a prioritized standup: CHANGES → CI-FAIL → CONFLICT → REVIEW → READY → WIP → DRAFT → STALE. Read-only. |
| **4. PR review orchestration** | [`agents/pr-reviewer.agent.md`](agents/pr-reviewer.agent.md) + [`skills/autoreview/`](skills/autoreview/) + [`skills/distributed-systems-pr-review/`](skills/distributed-systems-pr-review/) | Non-trivial review-ready diffs start with one isolated autoreview pass; the agent then applies full-repository judgment, verifies findings, and owns the final review. |
| **5. PR Author voice** | [`agents/pr-author.agent.md`](agents/pr-author.agent.md) + [`skills/distributed-systems-author-style/`](skills/distributed-systems-author-style/) | Upstream-ready titles, commit messages, and PR bodies in a distilled-maintainer style; pre-open self-review. Suggests `git`/`gh` commands; doesn't run them. |
| **6. Human-readable session titles** | [`extensions/session-title/`](extensions/session-title/) + [`scripts/session-title-hook`](scripts/session-title-hook) | Renames local chat and Copilot CLI sessions to the exact title of a GitHub PR or Issue linked in the prompt. |
| **7. Complete catalog** | [`CATALOG.md`](CATALOG.md) | All seven bundled agents and seven bundled skills, plus externally owned and commit-pinned recommendations. |

## Quick start

Install every bundled skill globally with the standard skills CLI:

```sh
npx skills@latest add JaydipGabani/agentkit --all --global
```

Clone the repository for custom agents, scripts, and memory templates:

```sh
gh repo clone JaydipGabani/agentkit
cd agentkit
$EDITOR INSTALL.md
```

The TL;DR for Claude Code on Linux:

```sh
# Agents and skills
mkdir -p ~/.claude/agents ~/.claude/skills
cp agents/*.agent.md    ~/.claude/agents/
npx skills@latest add "$PWD" --all --global

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

# Optional VS Code session-title automation
scripts/install-session-titles.sh
```

Full host-specific instructions (Claude Code, Cursor, Continue, Codex,
non-systemd setups) in [`INSTALL.md`](INSTALL.md).

## Repo layout

```
agentkit/
├─ agents/                     # general-purpose sub-agent prompts
│  ├─ daily-brief.agent.md
│  ├─ dependabot-round-robin.agent.md
│  ├─ gatekeeper-policy-author.agent.md
│  ├─ pr-author.agent.md
│  ├─ pr-reviewer.agent.md
│  ├─ session-log.agent.md
│  └─ worktree-setup.agent.md
├─ skills/                     # installable on-demand skill bundles
│  ├─ autoreview/              # vendored OpenClaw review harness
│  ├─ distributed-systems-pr-review/
│  ├─ distributed-systems-author-style/
│  ├─ distributed-systems-security-hardening/
│  ├─ gatekeeper-local-testing/
│  ├─ kubernetes-sig-auth-rigor/
│  └─ pr-review-dashboard/
├─ scripts/
│  ├─ install-session-titles.sh # package + install title automation
│  ├─ session-title-hook        # UserPromptSubmit bridge client
│  ├─ wt                       # git-worktree helper
│  └─ session-log-compile.sh   # daily digest compiler
├─ extensions/
│  └─ session-title/            # optional VS Code extension + tests
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
├─ examples/
│  └─ repos.txt                # session compiler repo-list template
├─ CATALOG.md                  # bundled and externally owned inventory
├─ upstream-skills.json        # audited upstream recommendation lock
├─ vendored-skills.json        # immutable vendored-source lock
├─ INSTALL.md
├─ LICENSE
└─ README.md
```

## Reuse model — what's portable, what isn't

| Layer | Portable? | Notes |
|---|---|---|
| **Agent prompts** (`agents/*.agent.md`) | Yes — pure Markdown + YAML frontmatter. | Use directly in VS Code or copy into another host's agent directory. |
| **Skills** (`skills/*/SKILL.md`) | Yes. | Most are pure Markdown; `autoreview` also bundles a cross-platform Python review harness and tests. |
| **Memories** (`memories/*.md`) | Yes, but the *install path* varies by host. | They're meant to be auto-loaded into every turn, not lazily fetched. |
| **`scripts/wt`** | Linux/macOS Bash. | Pure `git`/`bash`; no extra deps. |
| **`scripts/session-log-compile.sh`** | Linux/macOS Bash. Requires `jq`, `find`, `git`. Reads VS Code chat transcripts under `~/.vscode-server/data/User/workspaceStorage/`. | The transcript path is VS Code-specific. For other editors, point the script at the equivalent transcript directory. |
| **Session-title automation** | VS Code 1.132+, Node.js, and `gh` for PR metadata. | The hook is portable across local and remote VS Code extension hosts; title adapters are VS Code-specific. |
| **`systemd/`** | Linux with systemd user instance. | Provided as a starting point; macOS users want `launchd`, others want cron. The `systemd/README.md` covers conversions. |

## Compatibility

- **Editors**: VS Code custom agents use `.github/agents/*.agent.md`, and
  Copilot discovers skills under `.github/skills`, `.agents/skills`, or
  `.claude/skills`. The session-log compiler and optional session-title
  extension are the only pieces coupled to VS Code.
- **LLM hosts**: Claude Code can load the same Markdown from
  `~/.claude/agents` and `~/.claude/skills`. Cursor and Continue need
  light frontmatter or configuration adaptation.
- **OS**: Linux (primary) and macOS for the root scripts. Autoreview also
  includes a PowerShell harness for Windows. The Markdown is OS-agnostic.

## Provenance and credit

The locally authored PR review and author skills under `skills/` and the corresponding
notes under `memories/` are **abstracted patterns** distilled from the
public PR-review and commenting history of senior open-source
maintainers in the Kubernetes / OPA / Azure ecosystems. The raw mining
corpora — which contain personally-attributable phrasing and timing
data — are **not redistributed** in this repo. If you do similar
mining yourself, treat the corpus as private and publish only the
abstracted ruleset.

## Upstream skills

[`CATALOG.md`](CATALOG.md) records both the vendored OpenClaw autoreview
snapshot and the audited `sozercan/skills` recommendations. Vendored source is
checksum-locked; referenced source remains external.

## Talk / walkthrough

[`docs/talk-walkthrough.md`](docs/talk-walkthrough.md) is a 5-pillar
live demo doc — the same one used to walk teammates through the
toolkit. Open the linked artifacts as you go.

## Contributing

This is a personal toolkit shared for reuse, not a maintained product.
PRs that improve portability (more hosts, better fallbacks, fewer
hard-coded paths) are welcome.

Validate changes before pushing:

```sh
scripts/validate.sh
```

## License

[Apache-2.0](LICENSE), except the vendored OpenClaw autoreview skill, which is
MIT licensed. See [NOTICE](NOTICE) for provenance and attribution requirements.
