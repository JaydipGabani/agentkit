#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail() {
  printf 'validate: %s\n' "$*" >&2
  exit 1
}

frontmatter_has() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    NR == 1 && $0 != "---" { exit 2 }
    NR > 1 && $0 == "---" { closed = 1; exit }
    NR > 1 && index($0, field ":") == 1 { found = 1 }
    END { if (!found || !closed) exit 1 }
  ' "$file"
}

frontmatter_length() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, field ":") == 1 {
      sub(/^[^:]+:[[:space:]]*/, "")
      print length
      exit
    }
  ' "$file"
}

expected_skills=(
  autoreview
  distributed-systems-author-style
  distributed-systems-pr-review
  distributed-systems-security-hardening
  gatekeeper-local-testing
  kubernetes-sig-auth-rigor
  pr-review-dashboard
)

expected_agents=(
  daily-brief
  dependabot-round-robin
  gatekeeper-policy-author
  pr-author
  pr-reviewer
  session-log
  worktree-setup
)

for name in "${expected_skills[@]}"; do
  file="skills/$name/SKILL.md"
  [[ -f "$file" ]] || fail "missing $file"
  frontmatter_has "$file" name || fail "missing name frontmatter in $file"
  frontmatter_has "$file" description || fail "missing description frontmatter in $file"
  actual="$(awk -F': *' '/^name:/{print $2; exit}' "$file")"
  [[ "$actual" == "$name" ]] || fail "$file name is '$actual', expected '$name'"
  [[ "$actual" =~ ^[a-z0-9-]{1,64}$ ]] || fail "$file has an invalid skill name"
  (( $(frontmatter_length "$file" description) <= 1024 )) || fail "$file description exceeds 1024 characters"
  (( $(wc -l < "$file") <= 500 )) || fail "$file exceeds 500 lines"
done

for name in "${expected_agents[@]}"; do
  file="agents/$name.agent.md"
  [[ -f "$file" ]] || fail "missing $file"
  frontmatter_has "$file" name || fail "missing name frontmatter in $file"
  frontmatter_has "$file" description || fail "missing description frontmatter in $file"
  (( $(frontmatter_length "$file" description) <= 1024 )) || fail "$file description exceeds 1024 characters"
done

reviewer="agents/pr-reviewer.agent.md"
sed -n '2,/^---$/p' "$reviewer" | grep -Fxq 'tools: [read, search, execute]' || fail "PR Reviewer must not invoke ad-hoc reviewer subagents"
grep -Fq '### 0. Review orchestration' "$reviewer" || fail "PR Reviewer orchestration contract missing"
if grep -Fq '### 0. Multi-model orchestration' "$reviewer"; then
  fail "PR Reviewer duplicates autoreview model orchestration"
fi
grep -Fq 'The canonical `autoreview` skill exclusively owns external reviewer invocation' "$reviewer" || fail "PR Reviewer must delegate external review to autoreview"
grep -Fq 'Run autoreview exactly once per unchanged bundle.' "$reviewer" || fail "PR Reviewer must bound autoreview invocation"
grep -Fq '## External review' "$reviewer" || fail "PR Reviewer must report external review status"

[[ "$(find skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)" -eq "${#expected_skills[@]}" ]] || fail "unexpected top-level skill count"
[[ "$(find agents -maxdepth 1 -name '*.agent.md' | wc -l)" -eq "${#expected_agents[@]}" ]] || fail "unexpected agent count"

bash -n \
  scripts/session-log-compile.sh \
  scripts/wt \
  skills/autoreview/scripts/test-review-harness \
  skills/gatekeeper-local-testing/scripts/gator-local.sh \
  skills/gatekeeper-local-testing/scripts/kind-e2e.sh

command -v jq >/dev/null || fail "jq is required"
command -v python3 >/dev/null || fail "python3 is required"
jq -e '
  .version == 1 and
  .source.repository == "sozercan/skills" and
  .source.commit == "5cac953a24d54bbe613e4aa948dbf51b22468642" and
  (.skills | length) == 3 and
  ([.skills[].name] | sort) == (["a365-cli", "kindctl", "kusto-cli"] | sort)
' upstream-skills.json >/dev/null
jq -e '
  .version == 1 and
  (.skills | length) == 1 and
  .skills[0].name == "autoreview" and
  .skills[0].repository == "openclaw/agent-skills" and
  .skills[0].commit == "2a409d348a4bcf6f15e41e9a20efd0b298a32528" and
  .skills[0].tree == "386f855dc2f9bca568da5e3f1091c45ac5c1a36e" and
  .skills[0].license == "MIT" and
  .skills[0].localPayloadChanges == []
' vendored-skills.json >/dev/null

[[ "$(readlink skills/autoreview/CLAUDE.md)" == "AGENTS.md" ]] || fail "autoreview CLAUDE.md symlink changed"
(cd skills/autoreview && sha256sum --check --quiet UPSTREAM.sha256) || fail "autoreview payload differs from upstream"
python3 -m py_compile \
  skills/autoreview/scripts/autoreview \
  skills/autoreview/scripts/autoreview_test.py \
  skills/autoreview/scripts/test-review-harness.py
for check in \
  config-defaults fallback-scope engine-isolation heartbeat-metrics \
  json-array-parser opencode-jsonl-parser opencode-isolation cursor-jsonl-parser; do
  python3 skills/autoreview/scripts/autoreview "--self-test-$check"
done
python3 -m unittest \
  skills/autoreview/scripts/autoreview_test.py \
  skills.autoreview.tests.test_autoreview_hardening

for name in \
  Explore \
  address-pr-comments agent-customization chronicle create-pull-request \
  form-github-search-query get-search-view-results \
  kubernetes-correctness-pr-review kubernetes-feature-lifecycle-delivery \
  kubernetes-security-rollout-hardening project-setup-info-local \
  show-github-search-result suggest-fix-issue \
  summarize-github-issue-pr-notification; do
  grep -Fq "$name" CATALOG.md || fail "CATALOG.md does not account for $name"
done

payload_scan_failed=0
while IFS= read -r -d '' file; do
  if grep -InE '/home/funkydev|/mount/d/go/src|gho_[[:alnum:]]{20,}|github_pat_[[:alnum:]_]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' "$file"; then
    payload_scan_failed=1
  fi
done < <(find . -path ./.git -prune -o -path ./scripts/validate.sh -prune -o -type f -print0)
if [[ "$payload_scan_failed" -ne 0 ]]; then
  fail "host-specific path or credential signature found"
fi

dashboard="skills/pr-review-dashboard/scripts/dashboard_template.html"
grep -Fq 'https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js' "$dashboard" || fail "Mermaid URL is not pinned"
grep -Fq 'sha384-WmdflGW9aGfoBdHc4rRyWzYuAjEmDwMdGdiPNacbwfGKxBW/SO6guzuQ76qjnSlr' "$dashboard" || fail "Mermaid integrity is not pinned"

failed=0
while IFS= read -r -d '' file; do
  while IFS= read -r token; do
    link="${token#](}"
    link="${link%)}"
    link="${link%%#*}"
    case "$link" in
      ''|http://*|https://*|mailto:*|command:*|'~/'*|/*) continue ;;
    esac
    target="$(dirname "$file")/$link"
    if [[ ! -e "$target" ]]; then
      printf 'validate: broken local link: %s -> %s\n' "$file" "$link" >&2
      failed=1
    fi
  done < <(grep -oE '\]\([^)]*\)' "$file" || true)
done < <(find . -path ./.git -prune -o -type f -name '*.md' -print0)
[[ "$failed" -eq 0 ]] || exit 1

git diff --check
printf 'agentkit validation passed: %d skills, %d agents\n' "${#expected_skills[@]}" "${#expected_agents[@]}"
