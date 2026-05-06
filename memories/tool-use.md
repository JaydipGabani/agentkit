# Tool Use

- When using a sub-agent for validation, explicitly say not to edit files; it may otherwise fix failures with shell edits.
- Prefer running the workspace's first-class search tools (semantic / grep / glob / read) over shelling out (`grep`, `find`, `cat`) when the agent provides them — they're optimized for context windows and produce smaller diffs in chat.
- Read files before modifying them. Read large ranges in one call rather than many small reads.
- Run independent reads in parallel; run dependent operations sequentially.
- Never use destructive shortcuts (`--no-verify`, `--force`, `git reset --hard` on shared branches) without explicit confirmation.
