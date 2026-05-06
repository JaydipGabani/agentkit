# INSTALL.md

Step-by-step installation for the four pillars. Skip any pillar you
don't want.

> **Conventions.** Throughout this doc, `$REPO` is the path you cloned
> this toolkit into. `~/.local/bin` must be on your `PATH` for the
> scripts to be invokable.

---

## 1. Agents and skills

### Claude Code (primary target)

```sh
mkdir -p ~/.claude/agents ~/.claude/skills

# General-purpose
cp $REPO/agents/*.md  ~/.claude/agents/
cp -r $REPO/skills/*/ ~/.claude/skills/

# Optional: domain-specific examples
# cp $REPO/examples/agents/*.md       ~/.claude/agents/
# cp -r $REPO/examples/skills/*/      ~/.claude/skills/
```

Restart your Claude Code session (or reload its agents) so it picks
up the new files.

Verify routing: open a chat and ask "review this PR" — Claude Code
should delegate to `pr-reviewer`. Ask "what was I working on" — it
should delegate to `daily-brief`.

### Cursor

Cursor uses **Rules** (Cursor v0.50+). Open *Settings → Rules → User
Rules*, then for each agent or skill:

1. Create a new rule with a short title (e.g. "PR Reviewer").
2. Paste the body of the agent/skill `.md` file (skip the YAML
   frontmatter).
3. Set the rule's **trigger** to match the YAML `description` line
   from the original file.

Memories: paste each `memories/*.md` file into a single "Always-on"
rule.

### Continue (continue.dev)

Continue 0.9+ supports per-workspace `~/.continue/config.json`. Add
each agent under `customCommands`, with the agent body as the
prompt. Skills become entries under `slashCommands`. Memories go
into `systemMessage`.

### Copilot Chat (VS Code)

Copilot Chat reads `~/.github/copilot-instructions.md` (workspace
scope) and your global GitHub user settings. The simplest reuse:

1. Concatenate `memories/*.md` into a single document.
2. Paste into your **Copilot Chat custom instructions**.

Sub-agents are not first-class in Copilot Chat at time of writing,
so the agents become "modes" you invoke explicitly: paste the agent
body as a one-shot system prompt at the top of the chat.

---

## 2. Memories

The install path depends on the host:

- **Claude Code with the memory tool**: the tool exposes paths under
  `/memories/*.md`. Use the host's UI to create files matching the
  ones in `$REPO/memories/`. The on-disk backing location is
  host-specific.
- **Generic / other hosts**: paste the contents of each
  `memories/*.md` file into your global system prompt or "rules"
  config (see host-specific notes above).

**Pruning**: the auto-loaded memory display has a fixed line cap.
Keep entries terse; remove anything stale.

---

## 3. `wt` — git worktree helper

```sh
install -Dm755 $REPO/scripts/wt ~/.local/bin/wt
```

Smoke test:

```sh
cd ~/code/<some-repo>     # any git repo
wt list                    # should print the canonical worktree
wt new test-branch         # creates ~/worktrees/<repo>/test-branch
wt rm test-branch          # cleans up
```

No config required. Worktrees always live at
`~/worktrees/<repo>/<branch>`.

---

## 4. Daily session-log compiler

### Install the script

```sh
install -Dm755 $REPO/scripts/session-log-compile.sh \
   ~/.local/bin/session-log-compile.sh
```

### Configure repos to scan

Pick **one** of the three options:

**Option A — Config file (recommended).**

```sh
mkdir -p ~/.config/agentkit
cp $REPO/examples/repos.txt ~/.config/agentkit/repos.txt
$EDITOR ~/.config/agentkit/repos.txt
```

**Option B — Env var pointing at a different file.**

```sh
export AGENTKIT_REPOS_FILE=/path/to/your/repos.txt
```

**Option C — Auto-discovery.** Don't create a config file. The script
will scan `$AGENTKIT_SCAN_ROOTS` (colon-separated; default `$HOME`)
for `.git` dirs at depth ≤ 5.

### Smoke test

```sh
~/.local/bin/session-log-compile.sh
cat ~/.local/state/session-logs/$(date +%F).md
```

Expected: per-session blocks like

```
- **`<uid8>`** in `<repo>` (ws `<10char>`) — N user msg(s)
  - first: <opening prompt>
  - last:  <most recent prompt>
  - last edit: <file>
  - transcript: <abs path>.jsonl
```

### Schedule with systemd (Linux)

```sh
mkdir -p ~/.config/systemd/user
install -m644 $REPO/systemd/session-log-compile.service ~/.config/systemd/user/
install -m644 $REPO/systemd/session-log-compile.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now session-log-compile.timer
systemctl --user list-timers session-log-compile.timer
```

The unit re-reads the script every fire — no `daemon-reload` is
needed when you edit the script. Edit the units → `daemon-reload`.

To run on user logout / system suspend, ensure user lingering is on:

```sh
loginctl enable-linger "$USER"
```

### Schedule with cron (any Unix)

```cron
0 17 * * * $HOME/.local/bin/session-log-compile.sh >>$HOME/.local/state/session-logs/.cron.log 2>&1
```

### Schedule with launchd (macOS)

Adapt `systemd/session-log-compile.timer` into a `~/Library/LaunchAgents/<rdns>.session-log-compile.plist`
with a `StartCalendarInterval` block. Run `launchctl load` on it.

---

## Verification checklist

- [ ] `wt list` works inside a git repo.
- [ ] `~/.local/bin/session-log-compile.sh` runs without errors.
- [ ] Today's `~/.local/state/session-logs/<date>.md` has at least one
      session block.
- [ ] `systemctl --user list-timers session-log-compile.timer` shows a
      next-fire time (or your cron equivalent does).
- [ ] Asking your editor "what was I working on" routes to a
      `daily-brief`-style response.
- [ ] Asking "review this diff" routes to `pr-reviewer`.

---

## Troubleshooting

**The session-log compiler outputs nothing.**

- Confirm the transcript root exists:
  `ls ~/.vscode-server/data/User/workspaceStorage/`
- Confirm at least one transcript is recent:
  `find ~/.vscode-server/data/User/workspaceStorage -name '*.jsonl' -mmin -1440 | head`
- If you use VS Code Insiders or non-server VS Code, edit
  `TRANSCRIPT_ROOT` in `scripts/session-log-compile.sh`.

**`wt` says "not in a git repo".**

- You're not. `wt` requires the cwd be inside a git repo (canonical or
  worktree). Run `cd` into a repo first.

**Agents aren't routing to my installed `pr-reviewer`.**

- Verify the YAML `description` field is intact (some editors strip
  YAML frontmatter on copy).
- Restart the host so it re-scans the agents directory.

**systemd unit fails with "Read-only file system".**

- The hardening (`ProtectHome=read-only`) only allows writes under
  `~/.local/state/session-logs`. If you want it to write elsewhere,
  add another `ReadWritePaths=` line to the unit and reload.
