# scripts/

Shell helpers that back the agents.

## `wt` — git worktree helper

Wraps `git worktree` with a strong convention: canonical clone is the
shared shelf, every editable task gets its own worktree at
`~/worktrees/<repo>/<branch>`. Two agents working the same repo never
write to the same working tree.

### Common commands

```sh
wt new <branch> [base]   # create or attach worktree from base (default: origin/<default>)
wt cd <branch>           # print path; use as: cd "$(wt cd <branch>)"
wt list                  # list worktrees of the current repo
wt status                # short status across every worktree
wt rm [--force] <branch> # remove (refuses on dirty/unpushed)
wt prune                 # drop stale entries
wt root                  # print the canonical repo path
```

### Conventions

- Canonical clone path is whatever the user keeps as their primary
  checkout (e.g. `~/code/<org>/<repo>` or the Go layout
  `$GOPATH/src/github.com/<org>/<repo>`). `wt` itself is location-neutral.
- Worktrees always live under `~/worktrees/<repo>/<branch>`.
- Branch names with `/` are preserved on disk
  (e.g. `~/worktrees/<repo>/feat/foo`).

### Install

```sh
install -Dm755 scripts/wt ~/.local/bin/wt
```

Make sure `~/.local/bin` is on your `PATH`.

---

## `session-log-compile.sh` — daily session digest

Compiles a deterministic, read-only Markdown digest of the last 24 hours
of activity into `~/.local/state/session-logs/<YYYY-MM-DD>.md`.

### What it captures

For each VS Code Copilot Chat transcript active in the last 24 hours:

- session UID (stable across days — useful for finding cross-day threads),
- workspace storage hash (last 10 chars to disambiguate same-workspace
  re-opens),
- primary repo inferred from workspace folders,
- user-message count,
- first and last user prompt,
- last file edited via tool calls,
- absolute path to the `.jsonl` transcript.

For each repo it knows about: the previous day's `git log --oneline`,
dirty/unpushed status, and worktree expansion.

### Configuration

Repos to scan are read from (first hit wins):

1. `$AGENTKIT_REPOS_FILE` (env override)
2. `$XDG_CONFIG_HOME/agentkit/repos.txt`
3. `~/.config/agentkit/repos.txt`

One absolute path per line; lines starting with `#` are ignored. See
[`../examples/repos.txt`](../examples/repos.txt) for a sample.

If no config file is present, the script auto-discovers `.git`
directories under `$AGENTKIT_SCAN_ROOTS` (colon-separated; default
`$HOME`) at depth ≤ 5.

### Install (manual run)

```sh
install -Dm755 scripts/session-log-compile.sh ~/.local/bin/session-log-compile.sh
~/.local/bin/session-log-compile.sh           # produces today's digest
cat ~/.local/state/session-logs/$(date +%F).md
```

For unattended daily compile, install the systemd unit pair under
[`../systemd/`](../systemd/).

### Safety properties

- Read-only except for an append to the dated output file.
- `set -euo pipefail`; SIGPIPE-safe (jq output is drained to temp files
  before head/tail slicing).
- Skips empty/placeholder transcripts (msg count == 0).
- Sorts sessions by last activity, descending.
