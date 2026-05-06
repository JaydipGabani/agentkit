#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Jaydip Gabani
#
# session-log-compile.sh — deterministic daily summary of last 24h of activity.
# Read-only except for append to $OUTFILE. Safe for unattended cron/systemd.
#
# Configure repos to track in:
#   $XDG_CONFIG_HOME/agentkit/repos.txt   (preferred)
#   ~/.config/agentkit/repos.txt          (fallback)
# One absolute repo path per line; lines starting with '#' are ignored.
# If no config file exists, the script auto-discovers git repos under
# the directories listed in $AGENTKIT_SCAN_ROOTS (colon-separated;
# default "$HOME").
set -euo pipefail

SINCE_MIN=1440 # 24h
TRANSCRIPT_ROOT="$HOME/.vscode-server/data/User/workspaceStorage"
OUTDIR="$HOME/.local/state/session-logs"
mkdir -p "$OUTDIR"

TODAY="$(date +%Y-%m-%d)"
NOW="$(date +%H:%M\ %Z)"
OUTFILE="$OUTDIR/$TODAY.md"

# --- Repo list ---------------------------------------------------------------
CONFIG_FILE="${AGENTKIT_REPOS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/agentkit/repos.txt}"
REPOS=()
if [[ -f "$CONFIG_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    REPOS+=("$line")
  done < "$CONFIG_FILE"
fi
if [[ ${#REPOS[@]} -eq 0 ]]; then
  # Auto-discover: scan $AGENTKIT_SCAN_ROOTS (colon-separated) for top-level
  # git repos at depth ≤ 5. Skips worktrees (handled later via `worktree list`).
  IFS=':' read -ra scan_roots <<< "${AGENTKIT_SCAN_ROOTS:-$HOME}"
  for root in "${scan_roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r d; do
      REPOS+=("$d")
    done < <(find "$root" -maxdepth 5 -type d -name '.git' 2>/dev/null \
              | sed 's|/\.git$||' | sort -u)
  done
fi
# ----------------------------------------------------------------------------

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

################################################################################
# 1. Chat sessions active in last 24h
################################################################################
mapfile -t TRANSCRIPTS < <(
  find "$TRANSCRIPT_ROOT" -type f -name '*.jsonl' \
    -path '*/GitHub.copilot-chat/transcripts/*' -mmin "-$SINCE_MIN" 2>/dev/null | sort
)

session_count=${#TRANSCRIPTS[@]}
workspace_count=$(printf '%s\n' "${TRANSCRIPTS[@]}" \
  | awk -F/ '{for(i=1;i<=NF;i++)if($i=="workspaceStorage"){print $(i+1);break}}' \
  | sort -u | wc -l)

user_prompts_file="$tmp/prompts.txt"
tool_counts_file="$tmp/tools.txt"
files_edited_file="$tmp/files.txt"
terminal_cmds_file="$tmp/terminals.txt"
sessions_file="$tmp/sessions.tsv"
: > "$user_prompts_file" "$tool_counts_file" "$files_edited_file" "$terminal_cmds_file" "$sessions_file"

for t in "${TRANSCRIPTS[@]}"; do
  uid="$(basename "$t" .jsonl)"
  ws_hash="$(echo "$t" | awk -F/ '{for(i=1;i<=NF;i++)if($i=="workspaceStorage"){print $(i+1);break}}')"

  # Drain jq output to per-transcript temp files first (avoid SIGPIPE under set -o pipefail)
  um_tmp="$tmp/u_$uid.txt"
  fp_tmp="$tmp/f_$uid.txt"
  ts_tmp="$tmp/ts_$uid.txt"
  jq -rc 'select(.type=="user.message") | .data.content // empty' "$t" > "$um_tmp" 2>/dev/null || true
  jq -rc '
    select(.type=="tool.execution_start")
    | select(.data.toolName | test("replace_string_in_file|create_file|multi_replace_string_in_file|edit_notebook_file"))
    | (.data.arguments.filePath // .data.arguments.replacements[0].filePath // empty)
  ' "$t" > "$fp_tmp" 2>/dev/null || true
  jq -rc '.timestamp // empty' "$t" > "$ts_tmp" 2>/dev/null || true

  # First user prompt per transcript (signal of session intent)
  first_user="$(head -1 "$um_tmp" 2>/dev/null | sed 's/[[:space:]]\+/ /g' | cut -c1-140)"
  printf '%s\n' "$first_user" >> "$user_prompts_file" || true

  # Last user prompt (where the session left off)
  last_user="$(tail -1 "$um_tmp" 2>/dev/null | sed 's/[[:space:]]\+/ /g' | cut -c1-140)"

  # User message count (distinguishes quick query from deep work).
  # Use jq to count matching entries directly so multi-line message content doesn't inflate via wc -l.
  msg_count="$(jq -nr '[inputs | select(.type=="user.message")] | length' "$t" 2>/dev/null)"
  : "${msg_count:=0}"

  # Last write-tool target (where work stopped)
  last_edit="$(tail -1 "$fp_tmp" 2>/dev/null)"

  # Infer primary repo from edited file paths matching one of REPOS
  primary_repo=""
  for repo in "${REPOS[@]}"; do
    if [[ -s "$fp_tmp" ]] && grep -qF "$repo/" "$fp_tmp" 2>/dev/null; then
      primary_repo="$(basename "$repo")"
      break
    fi
  done

  # Last activity timestamp (for sort)
  last_ts="$(tail -1 "$ts_tmp" 2>/dev/null)"

  # Skip transcripts with no user messages (VS Code creates empty placeholder transcripts)
  if (( msg_count == 0 )); then
    continue
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$uid" "$ws_hash" "${primary_repo:--}" "$msg_count" "${last_ts:--}" \
    "${first_user:--}" "${last_user:--}" "${last_edit:--}" >> "$sessions_file"

  # Tool invocation counts
  jq -rc 'select(.type=="tool.execution_start") | .data.toolName // empty' "$t" 2>/dev/null \
    >> "$tool_counts_file" || true

  # Files edited (replace_string_in_file / create_file / multi_replace_string_in_file / edit_notebook_file)
  jq -rc '
    select(.type=="tool.execution_start")
    | select(.data.toolName | test("replace_string_in_file|create_file|multi_replace_string_in_file|edit_notebook_file"))
    | (.data.arguments.filePath // .data.arguments.replacements[0].filePath // empty)
  ' "$t" 2>/dev/null >> "$files_edited_file" || true

  # Terminal command first-tokens
  jq -rc '
    select(.type=="tool.execution_start")
    | select(.data.toolName | test("run_in_terminal|execution_subagent"))
    | (.data.arguments.command // .data.arguments.query // empty)
    | split("\n")[0] | split(" ")[0]
  ' "$t" 2>/dev/null >> "$terminal_cmds_file" || true
done

################################################################################
# 2. Git activity per repo + worktree
################################################################################
git_activity_file="$tmp/git.md"
: > "$git_activity_file"

declare -A seen_paths
for repo in "${REPOS[@]}"; do
  [[ -d "$repo/.git" || -f "$repo/.git" ]] || continue

  # Canonical + every worktree (dedup by absolute path)
  mapfile -t wts < <(git -C "$repo" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{print $2}')
  [[ ${#wts[@]} -eq 0 ]] && wts=("$repo")

  for wt in "${wts[@]}"; do
    [[ -n "${seen_paths[$wt]:-}" ]] && continue
    seen_paths[$wt]=1

    email="$(git -C "$wt" config user.email 2>/dev/null || true)"
    branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
    label="$(basename "$wt")"
    [[ "$wt" != "$repo" ]] && label="$(basename "$repo")/$(basename "$wt") [worktree]"

    commits=0
    if [[ -n "$email" ]]; then
      commits=$(git -C "$wt" log --since="24 hours ago" --author="$email" --oneline --all 2>/dev/null | wc -l | tr -d ' \n')
    fi
    dirty=$(git -C "$wt" status --short 2>/dev/null | wc -l | tr -d ' \n')
    unpushed=$( { git -C "$wt" log '@{u}..' --oneline 2>/dev/null || :; } | wc -l | tr -d ' \n')
    stashes=$(git -C "$wt" stash list 2>/dev/null | wc -l | tr -d ' \n')
    : "${commits:=0}" "${dirty:=0}" "${unpushed:=0}" "${stashes:=0}"

    # Skip uninteresting entries
    (( commits + dirty + unpushed + stashes > 0 )) || continue

    {
      printf -- "- **%s**" "$label"
      [[ -n "$branch" ]] && printf " (\`%s\`)" "$branch"
      printf ":"
      (( commits > 0 )) && printf " %d commits;" "$commits"
      (( dirty > 0 )) && printf " %d dirty files;" "$dirty"
      (( unpushed > 0 )) && printf " %d unpushed;" "$unpushed"
      (( stashes > 0 )) && printf " %d stashes;" "$stashes"
      printf "\n"
      if (( commits > 0 )); then
        git -C "$wt" log --since="24 hours ago" --author="$email" --pretty='    - %h %s' --all 2>/dev/null \
          | head -5
      fi
    } >> "$git_activity_file"
  done
done

################################################################################
# 3. Compose output (append-only)
################################################################################
{
  echo
  echo "## $NOW — auto-compiled (last 24h)"
  echo
  echo "### Sessions"
  if [[ -s "$sessions_file" ]]; then
    real_count=$(wc -l < "$sessions_file" | tr -d ' \n')
    echo "- $real_count chat transcripts touched across $workspace_count workspace(s)"
    echo
    # Sort by last_ts desc; emit per-session block
    sort -t $'\t' -k5,5r "$sessions_file" | \
      while IFS=$'\t' read -r uid ws repo msgs lt fu lu le; do
        short_uid="${uid:0:8}"
        # Use last 10 chars to preserve -2 suffix that VS Code adds to re-opened workspace dirs
        short_ws="${ws: -10}"
        repo_label="${repo:--}"
        printf -- "- **\`%s\`** in \`%s\` (ws \`%s\`) — %s user msg(s)\n" \
          "$short_uid" "$repo_label" "$short_ws" "$msgs"
        printf -- "  - first: %s\n" "$fu"
        if [[ "$fu" != "$lu" && -n "$lu" && "$lu" != "-" ]]; then
          printf -- "  - last:  %s\n" "$lu"
        fi
        if [[ -n "$le" && "$le" != "-" ]]; then
          printf -- "  - last edit: %s\n" "$le"
        fi
        printf -- "  - transcript: %s/%s/GitHub.copilot-chat/transcripts/%s.jsonl\n" \
          "$TRANSCRIPT_ROOT" "$ws" "$uid"
      done
  else
    echo "- $session_count chat transcripts touched across $workspace_count workspace(s)"
  fi

  echo
  echo "### Git activity"
  if [[ -s "$git_activity_file" ]]; then
    cat "$git_activity_file"
  else
    echo "- — no activity —"
  fi

  if [[ -s "$files_edited_file" ]]; then
    echo
    echo "### Notable files edited (top 15 by edit count)"
    sort "$files_edited_file" | uniq -c | sort -rn | head -15 \
      | awk '{c=$1; $1=""; sub(/^ /,""); printf "- (%d) %s\n", c, $0}'
  fi

  if [[ -s "$tool_counts_file" ]]; then
    echo
    echo "### Tool usage"
    sort "$tool_counts_file" | uniq -c | sort -rn | head -10 \
      | awk '{printf "- %s: %d\n", $2, $1}'
  fi

  if [[ -s "$terminal_cmds_file" ]]; then
    echo
    echo "### Top terminal/subagent first-tokens"
    sort "$terminal_cmds_file" | uniq -c | sort -rn | head -10 \
      | awk '{printf "- %s: %d\n", $2, $1}'
  fi
  echo
} >> "$OUTFILE"

echo "wrote $OUTFILE"
