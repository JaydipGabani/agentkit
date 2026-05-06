# Kubernetes SIG Auth Rigor (companion notes)

> **Provenance.** Distilled from the public review/issue-comment history of a senior `kubernetes/kubernetes` and `kubernetes/enhancements` maintainer focused on SIG Auth. The raw mining corpus is **not redistributed**; this file captures only the abstracted patterns. See `examples/skills/kubernetes-sig-auth-rigor/` for the agent-facing rendering.

Use this companion to `pr-review-techniques.md` whenever the change touches auth, RBAC, feature gates, KEPs, encryption-at-rest, or controller failure semantics.

## Most-cited rules

- **Compatibility first.** Tightening defaults must be opt-in; rollback path is mandatory ("This is a non-starter. You always have to be able to go back.").
- **Scope minimalism.** No theoretical use cases. Cite a real caller. "We can trivially expand this later if needed."
- **No `*` verb in bootstrap RBAC.** Enumerate exact verbs. Justify every added permission.
- **Authz checks are not feature-gate-able.** Cluster admin can broaden RBAC to bypass; the *check* always runs.
- **Mutually exclusive feature-gate wiring.** New filter logic in a new file; caller picks which to install. No mutation of the existing handler.
- **Tests run on both sides of the gate** when expected behavior is identical.
- **Terminal vs retryable.** Validation errors and ctx-cancel are terminal — mark object failed; never retry forever.
- **Counter-with-labels** beats N counters (`*_total{success|failure, ...}`). Beta requires metrics; GA never removes them.
- **Don't trust the abstraction for security.** Encryption-at-rest verification = read etcd directly.
- **Source-of-truth permalinks** (commit-pinned, line-ranged) — not "see file X".

## Phrasing to reuse verbatim

- "We can trivially expand this later if needed."
- "Why are we trying to handle theoretical cases?"
- "If it is required, I would drop the wildcard."
- "This is a non-starter. You always have to be able to go back."
- "I am unconcerned about code duplication — I want to make sure that the existing functionality cannot regress."
- "Authz errors are not fatal, follow this pattern: <permalink>"
- "Disable means it is impossible to use this feature through Kubernetes without setting the feature gate."
- "Drop this, metrics do not get removed once something is GA."
- "Explain the *why* here not the *what*."
- "Confirmed that this fails on `master` but passes on this PR."
