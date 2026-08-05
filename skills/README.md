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
| `gatekeeper-local-testing/` | Proving Gatekeeper changes with focused Go tests, Gator, kind, Helm, and generated VAP checks. |
| `kubernetes-sig-auth-rigor/` | Reviewing or authoring Kubernetes auth, API, RBAC, feature-gate, and version-skew changes. |
| `pr-review-dashboard/` | Explaining a checked-out PR as an interactive, single-file HTML dashboard. |

## How skills compose with agents

- `pr-reviewer` agent loads `distributed-systems-pr-review` always, plus
  `distributed-systems-security-hardening` if the diff touches RBAC,
  `securityContext`, GitHub Actions, etc.
- For Kubernetes diffs touching auth/RBAC/feature-gates, layer
  `kubernetes-sig-auth-rigor` on top.
- `pr-author` agent loads `distributed-systems-author-style` always.

## Installing

Install through `npx skills@latest add JaydipGabani/agentkit --all --global`,
or see [`../INSTALL.md`](../INSTALL.md) for host-specific paths.

## Provenance

Skills under this directory are **distilled patterns**, not raw mining
output. They were produced by analyzing the public PR-review history of
senior maintainers; the raw corpora are not included in this repo. If
you build a similar mining pipeline, treat the corpus as private and
publish only the abstracted ruleset.
