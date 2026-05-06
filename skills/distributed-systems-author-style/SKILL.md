---
name: distributed-systems-author-style
description: 'Author style guide for branches, commits, and PRs in distributed-systems projects (Kubernetes, Gatekeeper, secrets-store-csi-driver, etc.). Use when opening a PR, drafting a PR description, writing a commit message, or naming a branch — anywhere the goal is to communicate a change to upstream maintainers and reviewers. Distilled from a senior maintainer''s actual upstream contribution history.'
argument-hint: 'Change being authored (branch, PR, or commit)'
---

# Distributed-Systems Author Style

Use this skill when **authoring** a change for an upstream distributed-systems project. The conventions below are distilled from real merged PRs by an active upstream maintainer working across the Kubernetes, kubernetes-sigs, and Azure ecosystems.

This is the **authoring** counterpart to [`distributed-systems-pr-review`](../distributed-systems-pr-review/SKILL.md). Apply this *before* asking a maintainer to review — it preempts most surface-level feedback.

## 1. Branch naming

Use `<handle>/<type>/<slug>`.

- **`<handle>`**: your GitHub handle (e.g. `<yours>/c/fix-cves`, `<yours>/f/feature-name`).
- **`<type>`**: single-letter (or short) category:
  - `c/` — chore (version bumps, ownership, no-op triggers, feature-gate removals, CVE fixes)
  - `d/` — docs (README, KEP, identity-binding, rotation/upgrade docs)
  - `f/` — feature or fix landing in main
  - `r/` — release (manifest + helm chart bumps for a new version tag)
  - `ci/` — CI / workflow / Actions changes
- **`<slug>`**: lowercase `snake_case` (`fix_cves`, `pin_to_sha`, `kep_3331_implemented`, `release_v1.8.0`, `rm_anonymous_auth_fg`).

Example branches:

```
<yours>/c/fix-cves
<yours>/d/identity_binding_docs
<yours>/f/vap_validation
<yours>/r/release_v1.8.1
<yours>/ci/fix_govulncheck_workflow
```

Auto-generated branches (`automated-cherry-pick-of-#NNNN-upstream-release-X.Y`, `promote-vX.Y.Z`) come from `/cherry-pick` and image-promote tooling — leave them alone.

## 2. PR titles

**Length**: 25–70 characters. Median 52. Hard cap 80.

**Voice**: imperative mood (`Drop`, `Remove`, `Add`, `Bump`, `Fix`, `Promote`, `Update`).

**Prefix convention** (Conventional-Commits-style for non-Kubernetes-core repos):

| Prefix | Use for |
|---|---|
| `fix:` | bug fix |
| `chore:` | maintenance, version bumps, ownership, feature-gate removals, CVE fixes |
| `ci:` | CI / Actions / workflow / govulncheck changes |
| `docs:` | doc-only changes |
| `feat:` | new feature |
| `release:` | manifest/helm-chart updates for a new version tag |
| `security:` | dependency bumps to resolve CVEs |
| `build(docker):` / `fix(build):` | build-system scope (use parenthesized scope when narrow) |
| `docs(kep):` | KEP status updates |

**Kubernetes core (`kubernetes/kubernetes`, `kubernetes/k8s.io`)**: no prefix, plain imperative — `Drop StructuredAuthenticationConfiguration feature gate`, `Promote csi-secrets-store driver:v1.6.0`.

**Specificity is mandatory**: include version numbers, feature-gate names, package names, image tags. `fix: update grpc to v1.79.3 and golang to 1.26.2 to resolve CVEs` — not `fix: update deps`.

## 3. Commit messages

**Headline**: ≤ 72 chars (median 51, p90 66, hard cap 72). Same prefix system as PR titles. Imperative mood.

**Body**: present in 49 / 50 commits. Explain *why*, link upstream root cause when bumping a dep, paste failing-test output for bug fixes.

**Sign-off**: `Signed-off-by: <Name> <email>` is required by `kubernetes/*` and `kubernetes-sigs/*` (DCO check). Configure once with `git config commit.gpgsign true; git config user.email <email>` and commit with `git commit -s`. About two-thirds of merged commits in the corpus have it; add it by default for any k8s-org PR.

**Squash discipline**: keep one commit per logical change. A PR titled `fix: only set managed identity client ID when non-empty` should be one signed-off commit, not five WIP commits.

## 4. PR body

### For Kubernetes-org repos: follow the project template exactly

Sections, in order, using `####` headings:

```markdown
#### What this PR does / why we need it:

<one to three sentences. State the change AND the version-graduation reason if it's
a feature-gate removal: "Remove X feature gate. This feature became GA in 1.34 so
the gate is no longer needed as of 1.37.">

#### Which issue(s) this PR is related to:

<KEP link or issue number, or "N/A">

#### Special notes for your reviewer:

<anything skew-, downgrade-, or rollout-relevant. State explicitly if `--runtime-config=...`
is required in addition to the feature gate.>

#### Does this PR introduce a user-facing change?

```release-note
<one-line release note in user-visible language, OR `NONE` if no user-visible change>
```
```

Then `/kind <bug|cleanup|feature|api-change|deprecation|design|documentation|failing-test|flake|regression>` and `/sig <area>` on their own lines.

### For non-Kubernetes-org repos (Azure, sigs that don't use the k8s template)

Free-form prose, in this order:

1. **What and why** — one paragraph. State the bug or motivation.
2. **Root cause** — link the upstream issue, SDK PR, or commit that introduced it.
   > "This seems to be related to <link>. The bumped sdk is basically breaking the system-assigned identity option."
3. **Repro / failing test output** — paste the actual test failure in a fenced code block. Demonstrates the bug exists.
   ```
   === RUN   TestGetManagedIdentityTokenCredential
   --- FAIL: TestGetManagedIdentityTokenCredential ...
   ```
4. **Image SHAs / build URLs** — for image-promotion or release PRs, paste manifest digests and the Prow / GitHub Actions build URL.
5. **Reviewer assignment** — `/assign <handle>` at the end if there's a specific owner.

### Always-applicable elements

- **Link the KEP** when the change implements or graduates a Kubernetes feature.
- **Distinguish "feature gate enabled by default" from "also requires `--runtime-config=...`"** — both belong in the PR description if relevant.
- **Pin third-party Action versions to a SHA** when the diff touches a workflow.
- **Helm chart edits** belong in `manifest_staging/charts/<chart>/`, not `charts/`. State the staging path in the PR body if reviewers might miss it.
- **README values table** must be updated when adding a `values.yaml` key. Mention the parallel rows you followed (`logVerbosity`, `logFormatJSON`).
- **CRD lifecycle on uninstall** — call out the orphan story explicitly when a feature creates new CRDs.

## 5. Pre-open self-review

Run before pushing:

- [ ] Title fits the prefix table; ≤ 70 chars; imperative; specific (versions/names/IDs).
- [ ] Branch follows `<handle>/<type>/<slug>`.
- [ ] Each commit headline ≤ 72 chars, imperative, prefixed.
- [ ] `Signed-off-by:` present (any `kubernetes/*` or `kubernetes-sigs/*` repo).
- [ ] Single commit per logical change (squash WIP).
- [ ] PR body uses the project template (k8s repos) or the prose order above (others).
- [ ] Release-note block populated (k8s repos).
- [ ] KEP linked when applicable.
- [ ] `/kind` and `/sig` lines added.
- [ ] If touching a workflow: third-party Actions pinned to SHA.
- [ ] If touching a helm chart: edits in `manifest_staging/`; README values table updated.
- [ ] If feature-gated: graduation version stated; `--runtime-config` requirement stated if applicable.
- [ ] If a bug fix: failing-test output pasted in PR body.
- [ ] If a dep bump: upstream root-cause issue/PR linked.
- [ ] Then run the technical pre-merge checklist in [`pr-review-techniques.md`](~/memories/pr-review-techniques.md) (locks, error formatting, test-as-no-op, silent-fallback).

## 6. Tone

- **Direct.** No "I noticed that maybe we could..." — `Remove X feature gate.` is the model.
- **No filler.** No "thanks for reviewing", no "lmk what you think" in the body itself.
- **Backticks on every symbol/path/identifier** in the body and special-notes section.
- **Versions are facts, not opinions.** State `GA in 1.34` / `beta in v1.35` / `removed as of 1.37` — don't hedge with "I believe" or "I think".
