# examples/

Domain-specific artifacts shipped as **templates**, not as defaults.

These exist to show *how* to write your own per-repo agents and skills,
not because they're useful out of the box for someone who isn't working
on these specific projects.

## `agents/`

| Agent | Repo it targets | What to learn from it |
|---|---|---|
| `gatekeeper-policy-author.md`| `open-policy-agent/gatekeeper-library` | How to enforce a dual-engine (Rego + CEL) authoring story with tests, samples, and a `make generate` step. |

## `skills/`

| Skill | Source | What to learn from it |
|---|---|---|
| `kubernetes-sig-auth-rigor/` | Distilled from public SIG-Auth review history in `kubernetes/kubernetes` | How a domain-specific review skill complements the general `distributed-systems-pr-review` skill — RBAC scope, KEP requirements, feature-gate mutual exclusivity, encryption-at-rest verification. |

## `repos.txt`

Sample config for `scripts/session-log-compile.sh`. Copy to
`~/.config/agentkit/repos.txt` and edit.

## How to fork these into your own

1. Copy the file to `agents/` or `skills/` in your fork.
2. Replace the YAML frontmatter `description` with phrases your team
   actually uses ("bump spec" vs "release a new version" vs whatever).
3. Replace the repo-specific facts (paths, validation commands,
   filename conventions) with yours.
4. Remove the rules you don't have. **Smaller agents route better**
   than agents that try to cover every situation.
