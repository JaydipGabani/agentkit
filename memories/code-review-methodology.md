# Code Review Methodology

When reviewing code, PRs, diffs, or analyzing changes — always use **review mode** not Q&A mode.

## For every changed line/block, systematically ask:

1. **Invariants**: What API contracts, size limits, naming rules, or concurrency guarantees does this break?
2. **Consistency**: What parallel code paths do the same thing? Are they all updated consistently?
3. **State cleanup**: What state is touched (status objects, metrics, caches)? Is all of it cleaned up in every exit path?
4. **Input safety**: What are the inputs? Can any be nil, empty, oversized, or adversarial?
5. **Silent failure blast radius**: If this fails silently, what's the downstream impact?

## When asked about a specific line or function:

- Still scan the full diff for related patterns — don't tunnel-vision on the asked-about code.
- Check all call sites, not just the one in question.
- Look at surrounding code for inconsistencies with the change.

## Before saying "this looks correct":

- Cross-reference with platform limits (K8s name length 253, label length 63, etc.)
- Check for nil/zero-value safety on pointer parameters
- Verify error paths log or return — never silently swallow
- Confirm all similar code paths have the same guards
- **Read the implementation of wrapper types** — don't assume thin wrappers have pass-through semantics. `source.Channel` has fan-out; `sync.Pool` has no ordering; etc. One grep can prevent a wrong analysis.
- **When claiming "pre-existing behavior"** — verify by reading the actual old code, not by pattern-matching on surface similarity (same channel ≠ same semantics if the wrapping layer changes).
