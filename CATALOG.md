# Agentkit Catalog

Snapshot date: 2026-08-05.

This catalog separates content maintained in this repository from skills supplied by another repository, plugin, or editor extension. External content stays with its owner so updates, licensing, and trust boundaries remain clear. The active snapshot contains 8 agents and 20 skills: 7 agents and 7 skills are bundled here; the rest are runtime-managed references below.

## Bundled agents

| Agent | Purpose |
| --- | --- |
| [`Daily Brief`](agents/daily-brief.agent.md) | Summarize recent sessions, local Git state, and GitHub attention items. |
| [`Dependabot Round Robin`](agents/dependabot-round-robin.agent.md) | Drain Dependabot queues across the four OPA repositories. |
| [`Gatekeeper Policy Author`](agents/gatekeeper-policy-author.agent.md) | Author dual-engine Gatekeeper Library policies. |
| [`PR Author`](agents/pr-author.agent.md) | Prepare branches, commits, and pull request text. |
| [`PR Reviewer`](agents/pr-reviewer.agent.md) | Start non-trivial review-ready diffs with one isolated autoreview pass, then apply full-repository methodology and verify the final findings. |
| [`Session Log`](agents/session-log.agent.md) | Record a compact handoff for the next session. |
| [`Worktree Setup`](agents/worktree-setup.agent.md) | Isolate editable work before another agent can collide with it. |

## Bundled skills

| Skill | Purpose |
| --- | --- |
| [`autoreview`](skills/autoreview/SKILL.md) | Isolated, bundle-driven review through Codex, Claude, Pi, or Kimi. |
| [`distributed-systems-author-style`](skills/distributed-systems-author-style/SKILL.md) | Upstream branch, commit, and PR conventions. |
| [`distributed-systems-pr-review`](skills/distributed-systems-pr-review/SKILL.md) | Correctness-focused review for distributed systems. |
| [`distributed-systems-security-hardening`](skills/distributed-systems-security-hardening/SKILL.md) | Security, CI, RBAC, supply-chain, and rollout checks. |
| [`gatekeeper-local-testing`](skills/gatekeeper-local-testing/SKILL.md) | Focused Gatekeeper unit, Gator, kind, Helm, and VAP validation. |
| [`kubernetes-sig-auth-rigor`](skills/kubernetes-sig-auth-rigor/SKILL.md) | Kubernetes auth, API, RBAC, feature-gate, and version-skew rigor. |
| [`pr-review-dashboard`](skills/pr-review-dashboard/SKILL.md) | Interactive single-file HTML explanation of a checked-out PR. |

Install the bundled skills through the standard skills CLI:

```bash
npx skills@latest add JaydipGabani/agentkit --all --global
```

Agent installation is host-specific; see [`INSTALL.md`](INSTALL.md).

## Vendored upstream skills

| Skill | Source | Snapshot | License | Local payload changes |
| --- | --- | --- | --- | --- |
| `autoreview` | [`openclaw/agent-skills`](https://github.com/openclaw/agent-skills) | [`2a409d3`](https://github.com/openclaw/agent-skills/tree/2a409d348a4bcf6f15e41e9a20efd0b298a32528/skills/autoreview) | MIT | None |

See [`vendored-skills.json`](vendored-skills.json) and [`skills/autoreview/UPSTREAM.md`](skills/autoreview/UPSTREAM.md) for the immutable source and checksum details.

## Referenced, not redistributed

### Repository-owned skills

| Owner | Skills | Source |
| --- | --- | --- |
| Kubernetes | `kubernetes-correctness-pr-review`, `kubernetes-feature-lifecycle-delivery`, `kubernetes-security-rollout-hardening` | [`kubernetes/kubernetes/.github/skills`](https://github.com/kubernetes/kubernetes/tree/94f90f268e9abcc38ab6f92744ea321a075f9c2f/.github/skills) |

### Plugin and extension skills

| Owner | Skills |
| --- | --- |
| VS Code Copilot | `agent-customization`, `chronicle`, `get-search-view-results`, `project-setup-info-local` |
| GitHub Pull Requests extension | `address-pr-comments`, `create-pull-request`, `form-github-search-query`, `show-github-search-result`, `suggest-fix-issue`, `summarize-github-issue-pr-notification` |

The runtime-provided `Explore` agent is also referenced rather than copied. It supplies isolated, read-only codebase exploration and is updated with the host.

- The empty local `opa-maintainer-brief` directory is intentionally omitted because it has no `SKILL.md` or executable content.

## Evaluated upstream skills

Source: [`sozercan/skills`](https://github.com/sozercan/skills) at [`5cac953a24d54bbe613e4aa948dbf51b22468642`](https://github.com/sozercan/skills/commit/5cac953a24d54bbe613e4aa948dbf51b22468642), MIT licensed. The decisions are also recorded in [`upstream-skills.json`](upstream-skills.json).

| Skill | Decision | Rationale |
| --- | --- | --- |
| `kusto-cli` | Recommended | Useful for bounded, redacted AKS and Azure Data Explorer investigations. |
| `kindctl` | Conditional | Strong multi-worktree kubeconfig isolation, but it conflicts with `gatekeeper-local-testing`'s standard `kind-*` context ownership. Do not enable both for the same cluster until that helper is adapted to kindctl. |
| `a365-cli` | Not selected | Outside this toolkit's engineering workflow. |

The skills CLI does not clone a raw commit SHA directly. Use a detached local checkout for a reproducible install:

```bash
checkout="$(mktemp -d)/sozercan-skills"
gh repo clone sozercan/skills "$checkout"
git -C "$checkout" switch --detach 5cac953a24d54bbe613e4aa948dbf51b22468642
test "$(git -C "$checkout" rev-parse HEAD)" = 5cac953a24d54bbe613e4aa948dbf51b22468642
npx skills@latest add "$checkout" --skill kusto-cli --global -y
```

Install `kindctl` separately only after choosing its scoped-kubeconfig model:

```bash
npx skills@latest add "$checkout" --skill kindctl --global -y
```
