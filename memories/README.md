# memories/

"Memories" are short, hand-curated notes that the host (Claude Code,
Codex, etc.) auto-loads into every conversation. Think of them as
**stable system-prompt addenda** — distilled rules of thumb you don't
want to re-explain every session.

## File layout

| File | Purpose |
|---|---|
| `code-review-methodology.md` | The five-question lens applied to every changed line. Loaded by the `pr-reviewer` agent. |
| `pr-review-techniques.md`    | The seven concrete review moves + voice cues + repo conventions + pre-merge checklist. Distilled from senior maintainer history. |
| `sig-auth-rigor.md`          | Companion to the above for Kubernetes SIG-Auth diffs (RBAC, KEPs, feature gates, encryption-at-rest). |
| `worktree-workflow.md`       | The "one agent per worktree" rule, decision tree, and `wt` cheat sheet. |
| `tool-use.md`                | Tool-discipline rules (don't let validation sub-agents auto-fix; prefer first-class search; etc.). |

## Scope tiers

Hosts that support a memory tool typically expose three scopes; structure
your installed memories the same way:

- **User memory** (this directory's contents) — survives across all
  workspaces and conversations. Keep entries short.
- **Session memory** (`/memories/session/` if the host exposes it) —
  scoped to the current conversation. Throwaway notes, plans-in-flight.
- **Repository memory** (`/memories/repo/`) — workspace-scoped facts
  like "this project uses `make generate` after editing `src/`".

The files in this directory are **user-tier**.

## Installing

The path depends on the host:

- **Claude Code with the memory tool**: copy the markdown into the path
  the memory tool reports (often `~/.codex/memories/` is a common backing
  location, but it varies — ask your host).
- **Generic / Cursor / Continue**: include the contents of these files
  in your global system prompt or "rules" config.
- **Copilot Chat**: paste relevant excerpts into your custom
  instructions; or symlink into a directory the host watches.

See [`../INSTALL.md`](../INSTALL.md) for the full setup steps.

## Editing your own

- Keep entries terse. Memories are loaded into context on every turn —
  brevity is a feature.
- Use bullet points and single-line facts, not paragraphs.
- Update or remove entries that turn out to be wrong; do not let them
  rot.
- Prefer one topic per file. The auto-loaded display concatenates them
  in alphabetical order, so naming matters.

## Provenance for `pr-review-techniques.md` and `sig-auth-rigor.md`

These two files are the *abstracted* output of analyzing the public PR
review history of senior open-source maintainers. The raw mining
corpora are not redistributed here. If you want to do similar mining
on a maintainer of your choice, treat the corpus as private and
publish only the abstracted ruleset.
