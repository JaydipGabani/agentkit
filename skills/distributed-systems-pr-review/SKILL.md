---
name: distributed-systems-pr-review
description: 'Review pull requests and diffs in distributed-systems projects (admission controllers, API servers, controllers, sync engines, certificate rotators) for correctness, lifecycle bugs, cleanup safety, concurrency hazards, version-skew, operator impact, and missing tests. Use when asked to review a PR, review a diff, check if a change is safe to merge, or find real defects instead of style nits.'
argument-hint: 'PR, diff, or review target'
---

# Distributed-Systems PR Review (shared workflow)

Use this skill for non-trivial changes in any distributed-systems project (Gatekeeper, Kubernetes, cert-controller, frameworks/constraint, secrets-store-csi, etc.) where correctness, lifecycle behavior, version skew, and operator safety matter more than formatting.

This is the **shared workflow**. Repo-scoped skills add project-specific anchors on top.

## Review Workflow

1. **Read the diff and identify the runtime surfaces it changes.** Use `gh pr diff <n>` or `git diff <base>...<head>`. Don't read files one-by-one until you've seen the whole change.

2. **For non-trivial diffs, trace the flow first.** Restate the runtime sequence in 1–4 numbered steps and ask "is that the intent?". Surfaces design-level issues the code can't reveal on its own.

3. **For every changed block, apply the five lenses:**
   - **Invariants**: API contracts, wire format, defaults, validation, version-skew assumptions, size/length limits, naming rules, concurrency guarantees.
   - **Consistency**: Parallel code paths — are they all updated? Enum exhaustiveness? Dual implementations (Rego/CEL, internal/external types, generated/source)?
   - **State cleanup**: Status objects, metrics, caches, finalizers, watchers — cleaned up on every exit path including errors and ctx cancel?
   - **Input safety**: nil/empty/oversized/adversarial inputs at system boundaries. Pointer receivers. Slice/map zero values.
   - **Silent failure blast radius**: If this fails silently, what downstream gets corrupted? Any `err` swallowed or logged-and-continued?

4. **Apply the seven concrete moves to find defects:**

   **a. Future fragility, not just current correctness.** Code that works today but is fragile to a future change is a real issue. Name the future scenario concretely.

   **b. Lock-scope and race scrutiny.** For every mutex/atomic/channel touched:
   - Walk through every operation inside the critical section by name. Long critical sections are blockers.
   - Verify every read of a shared field is also under the same lock as writes. A field reassigned under lock but read without it is a data race regardless of intent.

   **c. Test-as-no-op detection.** For every new/changed test, ask: would this test fail without the production change? Common no-op patterns: wrong namespace, wrong message tag, setup that never triggers the path under test, mock that returns success regardless of input.

   **d. Silent-fallback / nil-default hazard.** Defaults that silently restore prior behavior on misuse — flip to error/panic so misuse is loud.

   **e. Error-formatting precision.** `fmt.Errorf("...: %w", err)` paths where `err` could be nil → message prints `<nil>`. Split the conditions.

   **f. Platform-limit and convention recall.** Cite limits by number; name parallel patterns to follow.

   **g. Source-of-truth discipline.** Generated files are not edit targets. Verify the change is in the authoritative source (staging, generator inputs, src/ template, CRD generator).

5. **Cross-cutting checks:**
   - Read wrappers before assuming pass-through semantics.
   - Check all call sites of changed functions, not just the one in the diff.
   - Verify error paths log *or* return — never both-silent.
   - For admission/webhook code: latency impact, hostile input, RBAC/secret exposure in logs.

6. **Distributed-systems-specific scrutiny:**
   - Admission/hot-path changes must preserve latency budgets.
   - Cleanup paths must not leave status, finalizers, metrics, or caches in a permanently inconsistent state.
   - Logs must include identifying resource keys and must not leak sensitive material.
   - Feature-gated/version-gated behavior must have a clear enablement, graduation, downgrade, and skew story.
   - Staging/generator changes may require propagation into generated code, docs, or consumers.

7. **Report only real issues** that could lead to defects, regressions, skew problems, or operational pain.

## Output Format

```
# Review: <PR title or diff scope>

## Flow as I read it
1. <step>
2. <step>
Is that the intent?

## Blocking
- **<file>:<line>** — <one-line issue>. <walkthrough>. <fix or fenced ```go suggestion```>.

## Non-blocking
- **<file>:<line>** — <future fragility / nit>.

## Questions (answer before merge)
- <targeted question>

## Verified clean
- <area you actively walked through and found nothing — be specific>
```

End with `/lgtm` only if there are no Blocking items AND `Verified clean` lists real, specific checks. Skip the `## Flow as I read it` section only if the diff is < 5 lines.

## Voice

- Direct. Get to the issue in the first sentence.
- Backticks on every symbol, path, identifier.
- `nit:` prefix only for stylistic comments. Never for correctness.
- Question form for added scope; declarative for bugs.
- Provide fix as fenced ` ```go ` or ` ```suggestion ` block when the fix is < 10 lines.
- No filler ("great work", "thanks for the PR", "this looks reasonable").

## Rules

- Do not spend most review energy on cosmetic nits when deeper correctness risks exist.
- If there are no findings, say that explicitly and call out residual risk or testing gaps.
- Do not claim "pre-existing behavior" without reading the actual prior code.
- Prefer direct, low-drama language grounded in the exact failure mode.
