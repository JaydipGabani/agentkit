# skills/

Skill bundles — focused, on-demand context that agents can pull in when
the task matches the skill's scope. Each skill is a directory with a
`SKILL.md` (the prompt) and optional supporting files.

## What each skill covers

| Skill | When to load |
|---|---|
| `distributed-systems-pr-review/` | Reviewing a diff in any distributed-systems repo (Kubernetes ecosystem, CRDs, controllers, webhooks, mesh, secrets management). Codifies the seven-move methodology. |
| `distributed-systems-author-style/` | Authoring or finalizing a PR in the same family of repos. Covers branch names, commit-message format, PR title prefixes, body templates, release-note blocks, `Signed-off-by`. |
| `distributed-systems-security-hardening/` | Whenever a change touches anything security-relevant: pinning actions to SHAs, `securityContext`, `RoleBinding`/`ClusterRoleBinding` scoping, image digests, supply-chain. |

Domain-specific skills (e.g. `kubernetes-sig-auth-rigor` — the SIG-Auth
KEP/RBAC/feature-gate rigor that surfaces in `kubernetes/kubernetes`
reviews) live in [examples/skills/](../examples/skills/) as templates.

## How skills compose with agents

- `pr-reviewer` agent loads `distributed-systems-pr-review` always, plus
  `distributed-systems-security-hardening` if the diff touches RBAC,
  `securityContext`, GitHub Actions, etc.
- For `kubernetes-org/*` diffs touching auth/RBAC/feature-gates, layer
  `examples/skills/kubernetes-sig-auth-rigor` on top.
- `pr-author` agent loads `distributed-systems-author-style` always.

## Installing

See [`../INSTALL.md`](../INSTALL.md). For Claude Code the convention is
`~/.claude/skills/<skill-name>/SKILL.md`. Other hosts use different
paths; the content (Markdown) is portable.

## Provenance

Skills under this directory are **distilled patterns**, not raw mining
output. They were produced by analyzing the public PR-review history of
senior maintainers; the raw corpora are not included in this repo. If
you build a similar mining pipeline, treat the corpus as private and
publish only the abstracted ruleset.
