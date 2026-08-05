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

[[ "$(find skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)" -eq "${#expected_skills[@]}" ]] || fail "unexpected top-level skill count"
[[ "$(find agents -maxdepth 1 -name '*.agent.md' | wc -l)" -eq "${#expected_agents[@]}" ]] || fail "unexpected agent count"

bash -n \
  scripts/session-log-compile.sh \
  scripts/wt \
  skills/gatekeeper-local-testing/scripts/gator-local.sh \
  skills/gatekeeper-local-testing/scripts/kind-e2e.sh

command -v jq >/dev/null || fail "jq is required"
jq -e '
  .version == 1 and
  .source.repository == "sozercan/skills" and
  .source.commit == "5cac953a24d54bbe613e4aa948dbf51b22468642" and
  (.skills | length) == 4
' upstream-skills.json >/dev/null

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
