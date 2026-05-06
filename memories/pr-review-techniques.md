# PR Review Techniques (distributed systems)

These are the techniques the `pr-reviewer` agent applies. Use the same checklist before requesting a maintainer review on your own PRs.

> **Provenance.** Distilled from the public PR-review history of senior maintainers in `open-policy-agent/*`, `kubernetes-sigs/secrets-store-*`, `kubernetes/kubernetes`, and `Azure/azure-workload-identity`. The raw mining corpus is **not redistributed**; this file captures only the abstracted patterns. See `skills/distributed-systems-pr-review/SKILL.md` for the agent-facing rendering.

## The seven moves applied to every diff

1. **Trace the flow.** Restate the runtime sequence in 1–4 numbered steps, ask "is that the intent?". Most distinctive move; surfaces design issues the code itself cannot.
2. **Future fragility.** "Today this works because X. But if a future change introduces Y..." — name the future scenario concretely.
3. **Lock scope.** Walk through every operation inside `Lock()/Unlock()` by name. Long critical sections are blockers. A field reassigned under lock but read without it is a data race regardless of intent.
4. **Test-as-no-op.** Walk through assertions. Tests that pass without the fix are a blocker. Common cases: wrong namespace, wrong message tag, missing setup that would trigger the changed code path.
5. **Silent-fallback hazard.** Nil-default fallbacks that silently restore old behavior — flip to error/panic so misuse is loud.
6. **Error formatting.** `%w` with nil error → `<nil>` in message; split conditions. No trailing punctuation; no capital first word.
7. **Platform limits + source of truth.** matchConditions ≤ 64/policy. K8s name 253, label 63, annotation 256 KiB. Helm: edit `manifest_staging/`, not `charts/`. Pin actions to SHA. State feature-gate version + `--runtime-config` requirement. Generated files → edit `src/`/staging/generator inputs.

## Voice cues

- Backticks on every symbol/path/file.
- `nit:` prefix only for stylistic comments, never correctness.
- Questions for added scope ("should we also...?", "could we pin...?"), declarative for bugs.
- Provide fix as fenced ` ```go ` or ` ```suggestion ` block when ≤ 10 lines.
- No "great work" / "thanks" / "looks reasonable" filler.
- Brief on chore PRs: `/lgtm`, `/azp run pr-e2e`.

## Repo conventions (examples)

- **secrets-store-csi-driver / secrets-store-sync-controller**: chart edits go in `manifest_staging/charts/<chart>/` only. `values.yaml` additions need matching row in README values table.
- **GitHub Actions** (any repo): pin third-party actions to a SHA.
- **Gatekeeper**: VAP generation parity with constraint operations; matchConditions consolidation; CRD lifecycle on uninstall; Rego/CEL parity.
- **Kubernetes / KEPs**: link the KEP from the PR, state graduation version, distinguish "feature gate enabled by default" vs. "also requires `--runtime-config=...`". Edit staging, not generated code.
- **gatekeeper-library**: edit `src/` and run `make generate`; never hand-edit `library/**/template.yaml`.

## Pre-merge checklist

- [ ] Tested the test: would this test fail without my code change? (Flip the bit and re-run.)
- [ ] Every `Lock()`–`Unlock()` walked through? Anything blocking inside?
- [ ] Every shared field read under the same lock as its writes?
- [ ] Any nil-default that silently restores prior behavior? → make it loud.
- [ ] `fmt.Errorf("...%w", err)` paths: can `err` be nil here?
- [ ] Helm chart change in `manifest_staging/`? README updated?
- [ ] Action pin is a SHA, not a tag?
- [ ] Feature-gate version + runtime-config flag both stated in description?
- [ ] CRD/orphan story for uninstall?

For non-technical pre-merge items (branch name, commit-message format, PR title prefix, PR body template, release-note block, `/kind`+`/sig`, `Signed-off-by`), use the `pr-author` agent and the `skills/distributed-systems-author-style` skill.

For auth / RBAC / feature-gate / KEP rigor specifically (Kubernetes-org repos), layer in `examples/skills/kubernetes-sig-auth-rigor`. Companion notes: `memories/sig-auth-rigor.md`.

Agent definitions:
- Reviewer: `agents/pr-reviewer.md` — triggers: "review this", "code review", "is this safe to merge", "review mode".
- Author:   `agents/pr-author.md`   — triggers: "open PR", "draft PR", "write commit message", "self-review my branch", "name this branch".
