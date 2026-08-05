---
name: kubernetes-sig-auth-rigor
description: 'Engineering rigor for contributing to Kubernetes and other distributed-systems projects, focused on the auth/API/controller surfaces (kube-apiserver filters, RBAC, authentication, authorization, encryption-at-rest, KMS, JWT/OIDC, ServiceAccount tokens, certificates, controllers). Use when designing or implementing a feature, writing a KEP, drafting feature-gate wiring, adding RBAC, designing audit/observability, or reasoning about upgrade/downgrade/version-skew. Distilled from a senior SIG Auth maintainer''s actual review history.'
argument-hint: 'Feature, KEP, or change to apply Kubernetes SIG Auth-grade rigor to'
---

# Kubernetes SIG Auth Rigor

Use this skill when **authoring or reviewing** non-trivial changes in Kubernetes (or any distributed-systems project that ships behind a stability contract — feature gates, API versions, RBAC). It captures the rigor patterns distilled from a senior SIG Auth maintainer's actual upstream contribution and review history across `kubernetes/kubernetes` and `kubernetes/enhancements`. Pair with [`distributed-systems-pr-review`](../distributed-systems-pr-review/SKILL.md) (review workflow) and [`distributed-systems-author-style`](../distributed-systems-author-style/SKILL.md) (PR/branch/commit style).

The principles below are quoted from real review utterances. Treat the quotes as the canonical phrasing — use them when pushing back, requesting follow-ups, or explaining tradeoffs.

## 1. Compatibility comes first; tightening is opt-in

- **Do not silently tighten existing behavior.** Tightening defaults that change cluster startup or admission outcomes is a non-starter unless it lands behind an opt-in flag, gated for at least one release at beta-on-by-default before any dependent KEP can graduate.

  > "The default today is no TLS verification at all so it does not make sense for us to tighten this in a way that will just cause upgrade failures." — senior SIG Auth maintainer reviewing a KEP, switching the proposal from on-by-default to opt-in.

- **Always preserve a rollback path.** If a feature cannot be safely disabled or downgraded, redesign it so it can.

  > "This is a non-starter. You always have to be able to go back."

- **Downgrade gating crosses release boundaries.** A feature gate that some other feature depends on must be on by default at least one release before the dependent feature graduates.

  > "`ServiceAccountNodeAudienceRestriction` feature gate is beta in KAS and enabled by default. This feature needs to be beta/enabled by default at least one release before this KEP goes to beta. This is critical to support downgrade use cases."

- **Code duplication is acceptable when the price is regression risk.** When wiring a substantial rewrite of a critical filter, build the new path next to the old one rather than mutating the old one.

  > "I am unconcerned about code duplication — I want to make sure that the existing functionality cannot regress and I expect us to do a near complete rewrite of impersonation to have an efficient implementation."

## 2. Scope minimalism: relax later, never tighten later

- **Do not support theoretical use cases.** Default to the smallest API surface that the known callers actually exercise. You can always add later; you cannot remove without breaking users.

  > "That is not a valid reason. If the kubelet doesn't do it, then we don't allow it. There is no need to support things without evidence. We can trivially expand this later if needed."

  > "Even an uber driver would likely update each driver separately? Regardless, why are we trying to handle theoretical cases? We can always relax things later if needed."

- **Cite a concrete caller for every supported case.** If a reviewer asks "do we actually have a use case for X?" and you can't answer with a real production caller, drop X.

  > "Do we actually have a use case for abstract sockets here?"

- **Trim PRs ruthlessly.** Pure scope expansion that wasn't asked for in the KEP belongs in a follow-up.

## 3. Authorization, RBAC, and least privilege

- **No wildcards in controller bootstrap policy.** Enumerate the exact verbs the controller needs.

  > "This is unsound, and is effectively cluster admin. Do not use `*`. Enumerate the exact permissions this controller needs."

  > "Enumerate the exact verbs needed."

- **Justify every added permission.** A new `patch` or `update` verb on a controller deserves a one-line comment explaining the precise call site that needs it.

  > "Why did you add `patch`?"

  > "Add comment about why this RBAC is needed."

- **Authorization checks are not optional and cannot be feature-gated off.** If granular enforcement is too tight, the cluster admin can grant the broader binding to `system:authenticated` — but the check itself must always run so all clusters behave identically.

  > "The authorization checks are not optional and cannot be disabled. The cluster admin can always choose to grant this access to `system:authenticated` if they do not wish to have granular enforcement, but they cannot prevent the check from running. This keeps the behavior in all clusters identical."

- **Authz errors are not fatal.** Distinguish "the authorizer said no" from "the authorizer crashed" — non-fatal denials follow the established pattern (see `staging/src/k8s.io/apiserver/pkg/endpoints/filters/impersonation/mode.go`).

  > "Authz errors are not fatal, follow this pattern: <permalink to mode.go>"

- **Use `AttributesRecord` correctly.** Every authz check belongs in an API group you control, with a verb specific to the action being authorized, with `ResourceRequest: true` for resource-level checks. Reference `IsAuthorizedForSignerName` as the canonical pattern.

  > "You are misunderstanding how to use this API. See `IsAuthorizedForSignerName` for an example."

  > "Use a verb specific to the authz" / "the API group must be one we control"

- **Cluster-scoped resources never go in `admin`/`edit`/`view`.** Those cluster roles are meant to be bound by a `RoleBinding` in a specific namespace.

  > "Cluster scoped resources are not in scope for the `admin`, `edit`, `view` cluster roles which are only expected to be bound via a role binding in specific namespaces."

- **Audit annotations document why a request was authorized.** Any new authz path that branches on subject identity or context should emit an audit annotation describing the reasoning.

  > "We probably should have audit annotations that describe the reasoning behind why the impersonation was allowed."

- **Don't hand the authorizer arbitrary user-controlled labels.** Domain-qualify any new field name (`k8s.io:impersonate-on:`) to reduce conflicts.

## 4. Feature-gate wiring discipline

- **Make the gates mutually exclusive, not stacked.** New filter logic must be in a new file (`constrained_impersonation.go`), gated by a new feature gate, with the caller picking which filter to install. Do not mutate the existing handler.

  > "Please update the feature gate check so the caller decides to use the existing `WithImpersonation` or a new `WithConstrainedImpersonation`. There should be no changes made to `.../filters/impersonation.go` and `WithConstrainedImpersonation` should be in a new file `.../filters/constrained_impersonation.go`."

- **`Disable` means the field is unset or causes an error on use.** It is not "the controller silently ignores the field."

  > "Disable means 'it is impossible to use this feature through Kubernetes without setting the feature gate.' Thus when the feature gate is disabled, the field would be explicitly unset (or cause an error on use)."

- **Run every test twice — once with the gate on and once with it off.** When the expected behavior is identical, both invocations must pass against both code paths.

  > "Also update `./pkg/endpoints/filters/impersonation_test.go` such that it runs twice — once with `WithContrainedImpersonation` and once with `WithImpersonation` — the result should be the same."

  > "Also run this same test with the feature gate turned off."

  > "Add this same test with the feature gate disabled which should cause it to not error."

- **Feature-gate runtime checks must check API enablement too.**

  > "Feature gate + check the API is enabled."

- **Bootstrap RBAC for an alpha feature must itself be feature-gated.**

  > "Also, these rules must be feature gated since this functionality is not GA."

## 5. KEP rigor (graduation, version skew, downgrade)

When writing or reviewing a KEP, every section below must be filled in concretely. Vague language gets a "complete this" comment; missing sections block PRR.

- **Version skew section:** Walk through how an n-3 kubelet, an n-1 kube-controller-manager / kube-scheduler, and CRI/CSI/CNI components without this feature behave. Cite the exact behavior, not a generic statement.

- **Upgrade / downgrade strategy:** State the exact required cluster-admin action on upgrade. State whether kubelets must be drained. State whether pods must be deleted. Explicitly answer "can this be made automatic?".

  > "Describe the steps explicitly. Do kubelets need to be drained?"
  > "As in, the pods need to be deleted?"
  > "Can this be made automatic?"

- **Mermaid diagrams for non-trivial flows.** Show the feature gate on and off paths.

  > "Convert this flow into one or more mermaid diagrams. Include the feature gate being on and off."

- **For new authz/admission paths, paste the exact SAR YAML.** Reviewers should not have to read code to know what authorization request the API server will issue.

  > "Include the exact YAML of the subject access review that will be sent to the authorizer chain."

- **GA gating includes adoption proof, not just code completeness.** Real production adoption of each user story is required before graduating.

  > "I would like to see at least one successful adoption of each user story (node agent and deputy) before we GA."

- **Conformance is a GA-bucket activity, not earlier.**

  > "I believe all we would need in this bucket is an eventual conformance test as part of GA. Otherwise it should be easy to test this feature via unit and integration tests."

- **Feature-gate removal is post-GA, never co-graduation.**

  > "Feature flag removal is a post GA activity."

- **PRR sections are not boilerplate.** "Difficult to review this from a PRR standpoint since this is not a valid approach for an alpha feature." — fill them in with the actual rollback / observability / test answers.

- **Mark `status: implementable` only when the design is settled.** Update `latest-milestone`, `feature-gates`, `disable-supported`, and `metrics` blocks honestly.

## 6. Failure semantics: terminal vs retryable

A controller that retries forever is a bug. Classify every error path:

- **Terminal (mark migration / object as failed).** Validation errors that can never succeed. Context-cancelled errors. Errors from impossible-to-recover conditions.

  > "If this is a non-integer, this will fail validation and become a terminal state where we do not want to retry."
  > "All the error says is that the context got canceled meaning it timed out. Retrying won't help because the context is already cancelled so all retries will fail."
  > "I don't think we can recover from this by retrying so should this also fail the migration?"

- **Retryable with backoff.** Use the rate limiter; honor `SuggestsClientDelay`; take the max of the two so you don't undercut your own limiter.

  > "Use this to backoff for the seconds indicated via `SuggestsClientDelay`."
  > "`svmc.queue.AddAfter(key, max(time.Second*time.Duration(suggestDelay), svmc.rateLimiter.When(key))` — in case our rate limiter tells us to wait longer."

- **Restrict the allowable error set explicitly.**

  > "The only allowable error is conflict. It is impossible for SSA to return a not found"

## 7. Observability and metrics

- **Counter-with-labels over many counters.** A single `*_total` counter with `success`/`failure` (and other dimension) labels collapses what would otherwise be N separate metrics.

  > "I would call the metric something like `kube_apiserver_validation_kubelet_cert_cn_total` and have a `success` and `failure` label."
  > Condense N scenario counters to one labeled metric: counter with labels `adminaccess` (`true`/`false`), `status` (`success`/`failure`).

- **Beta requires metrics.**

  > "Generally speaking, metrics are required for beta."

- **Metrics never get removed once GA.**

  > "Drop this, metrics do not get removed once something is GA."

- **Don't reuse per-token labels for cluster-wide info.** Beta-but-not-GA features whose labels can be empty should skip the metric until GA, not emit empty-label series.

  > "I think until it goes GA, we should probably skip these metrics altogether if the ID is empty."

- **Hashes that span configuration are external API.** Document them as such; never concatenate sub-hashes (collision-prone).

  > "I don't know if this is safe, `hash(A) || hash(BC)` `==` `hash(AB) || hash(C)`"
  > "Need some comment about this hash being an external API."

- **Custom collectors over event-time bookkeeping.** When a metric depends on the steady-state shape of a queue or cache, walk the queue inside a custom collector. Event counters drift.

  > "IMO a custom collector (maybe with a cache) that just looks at the entire queue contents would be easier to reason about / more likely to be correct."

## 8. Validation and API design

- **Use existing types.** `metav1.GroupResource`, not a custom struct with two strings.

  > "`Resource metav1.GroupResource`" + "delete the `GroupResource` struct below."

- **`field.Required` for empty strings, `ValidateImmutableField` for whole specs.**

  > "Return `field.Required` error when resource is empty."
  > "Replace this logic with a call to `ValidateImmutableField` for the whole `Spec`."

- **Tighten the new API even when the existing one was loose.**

  > "We also know that Go is going to tighten cert validation so let's be stricter on this new API from the start: no DNSNames entries are `\"\"` or contain `..` or start/end with `.`; EmailAddresses all pass `mail.ParseAddress`."

- **Untrusted fields must be named `untrusted` / `unverified`.**

  > "Please add something like `untrusted` or `unverified` to the name of the field."

- **API review covers backwards-compatible-or-not classification.**

  > "For API review since this is not technically backwards compatible."

- **Built-in APIs need protobuf tags.** Don't drop them on the way to a built-in API.

## 9. Security: don't trust the abstraction

- **Encryption-at-rest verification means reading etcd directly.** Metrics can lie; the encryption layer is by design transparent and can appear to work while broken.

  > "For validating the state of encryption at rest, nothing but directly checking the contents of etcd is ever actually sufficient. It is by design transparent to the rest of the system, and can appear to work while being broken. This is why we test encoding and transformation logic in integration tests by directly checking etcd contents."

- **Caches are not security-decision inputs.**

  > "Do not use the cache for a security check."

- **Static config validation > runtime validation.** Don't push checks to runtime if you can express them at config-load time.

  > "I don't really want to push the checks to runtime since we will lose the already minimal static validation we have on the expressions."

- **Tokens that "never expire" don't rotate.** External signers that issue long-lived SA tokens cannot rotate without consumer-side coordination — explicitly call out that this constraint forces the design.

## 10. Tests: assert against the real shape, not the mock

- **Test helpers must not return errors.**

  > "Test helpers should not return errors."

- **No test-level globals.** They make `t.Parallel` impossible and create cross-test bleed.

  > "Can we not have a test level global? It tends to make it impossible to run tests in parallel."

- **`atomic.Pointer[T]` over typed-via-`interface{}`.** Type safety in concurrent test plumbing.

  > "Use atomic ptr for type safety."

- **Confirm the test fails on master.** Test-the-test is mandatory for bug-fix PRs.

  > "Confirmed that this fails on `master` but passes on this PR."

- **Assert the actual external surface.** Headers, audit log entries, authz attributes — not just "no error returned".

  > "Assert the headers seen by the filter and the authz checks does by it as well, see [this test](https://github.com/vmware/pinniped/.../impersonator_test.go#L437-L553) as an example."

- **`testify` consistency.** Don't mix `require` / raw `t.Fatal` / `gomega` in one test file.

  > "Consistently use testify for all assertions."

- **Add unit tests for nested errors.**

  > "Add unit test with nested kube API error like `fmt.Error(\"bad thing: %w\", apierrors.NewForbidden(...))`"

- **For metrics-correctness, run integration tests, not unit tests.** Unit tests validate the call site; integration tests validate the steady-state shape.

  > "I am sure the unit tests will always pass since they do not run in a real env but I am unsure if the metrics from this will actually be correct or just close to correct."

## 11. Comments: explain *why*, not *what*

- **Document non-obvious constraints.**

  > "Add a comment that states this is only used with `parallelHandler`."
  > "Add comment about why this hash being an external API."
  > "Add comment about why this RBAC is needed."

- **Explain *why*, not *what*.**

  > "Explain the *why* here not the *what*. I don't immediately know why you needed to change this file."

- **A `Clean()` call needs a comment.** A non-obvious stdlib call belongs at a higher level, or has a comment.

  > "I don't understand why you need this `Clean` call here? If we do need it, it should be done at a higher level I think."

## 12. Source-of-truth permalinks

- **Cite by permalink (commit-pinned URL with line range), not by file path.** Reviewers click through; line numbers drift.

  > "I would be stricter here, see https://github.com/kubernetes/kubernetes/blob/<sha>/staging/src/k8s.io/apiserver/pkg/endpoints/filters/impersonation/mode.go#L595-L633"

- **When you say "follow this pattern," paste the URL.** Do not say "see the X file" without anchor.

- **When citing standards, link RFCs and SPIFFE specs.** "My reading of the RFCs ..." with two RFC links is the model.

## 13. Voice and process commands

- **`/lgtm` and `/approve` are separated.** Defer one of them to the named owner when appropriate. Approval ownership is a real boundary.

  > "/lgtm /approve" and "Deferring `/lgtm` to @stlaz and `/approve` to @jpbetz"

- **`/hold` always with a reason.** API review pending. Slack thread linked. Accidental-merge prevention before owner sign-off.

  > "/hold — There are behavioral changes in go-oidc v3 that don't match what I would expect from KAS"
  > "/hold — Per <slack thread>"
  > "/hold — To prevent accidental merge before API review."

- **`/milestone vX.Y` explicit.** Don't let it default. Re-`/milestone` on each cycle if you defer.

- **`/release-note-edit`** with a fenced ` ```release-note ... ``` ` block when you change the user-facing wording.

- **`/retest` only with a stated reason (or `/retest-required` for required jobs).**

  > "/retest-required — (unclear if the unit test failure is related, the linter hint is fine to ignore)"

- **`/sig <area>` and `/triage accepted`** are not optional on KEPs and substantive PRs.

- **Disagreement is direct and short.** Don't waffle.

  > "I don't find this reasoning compelling."
  > "This is unsound."
  > "This is a non-starter."
  > "That is not a valid reason."

- **Admit when wrong, briefly.**

  > "Sorry, ignore me, I read the description without reading the code."
  > "Ah okay, we can leave it as-is for now."

- **Backticks on every symbol, path, file, identifier, flag, verb.**

- **Use suggestion blocks for fixes ≤ 10 lines.** Saves the author a round-trip.

## 14. Pre-flight checklist (use before opening a SIG Auth PR)

In addition to the [`distributed-systems-author-style`](../distributed-systems-author-style/SKILL.md) checklist:

- [ ] Every new RBAC rule has explicit verbs (no `*`) and a comment explaining the call site.
- [ ] Every new feature gate has: a constant in `kube_features.go`, a `// alpha: vX.Y` comment, a versioned-feature-list YAML entry, runtime check at the wiring site, and a unit test for both states.
- [ ] Every new authz check uses `AttributesRecord` with: a verb specific to the action, an API group you control, `ResourceRequest: true` for resource scope.
- [ ] Every controller error is classified as terminal vs retryable; terminal errors mark the object failed, retryable errors honor the rate limiter.
- [ ] Every new metric is `*_total` or `*_seconds`, has minimal label cardinality, has documented label semantics, and has a unit test that asserts metric output for both success and failure.
- [ ] If the change tightens an existing default, it is opt-in via a new flag/gate.
- [ ] If the change adds a field to a config that has automatic reload, the implication for partially-upgraded clusters is described in the PR body.
- [ ] If the KEP graduates to beta, prior-release downgrade compatibility is explicitly stated.
- [ ] KEP version-skew section walks n-3 kubelet / n-1 KCM/scheduler explicitly.
- [ ] KEP includes the literal SAR YAML and (for non-trivial flows) a mermaid diagram with the gate on and off.
- [ ] Tests run against both states of the feature gate, where behavior should be identical.
- [ ] Audit annotations exist for any new authorization branching.
- [ ] Hashes/strings exposed in metrics or status are documented as external APIs.
- [ ] Source-of-truth (staging, generator inputs, kep template) was edited — not the generated artifact.

## 15. Phrases to use verbatim when pushing back

Keep these exact phrasings handy. They are short, declarative, and have been used successfully to gate substantive design changes:

- "We can trivially expand this later if needed."
- "We can always relax things later if needed."
- "Why are we trying to handle theoretical cases?"
- "Do we actually have a use case for X here?"
- "If it is required, I would drop the wildcard."
- "Enumerate the exact verbs needed."
- "This is a non-starter. You always have to be able to go back."
- "This is unsound, and is effectively cluster admin."
- "I don't find this reasoning compelling."
- "Authz errors are not fatal, follow this pattern: <permalink>"
- "Make it opt-in to retain backwards compatibility."
- "I am unconcerned about code duplication — I want to make sure that the existing functionality cannot regress."
- "Feature flag removal is a post GA activity."
- "Disable means it is impossible to use this feature through Kubernetes without setting the feature gate."
- "Generally speaking, metrics are required for beta."
- "Drop this, metrics do not get removed once something is GA."
- "Explain the *why* here not the *what*."
- "Confirmed that this fails on `master` but passes on this PR."
- "Test helpers should not return errors."
- "Do not use the cache for a security check."
- "For validating the state of encryption at rest, nothing but directly checking the contents of etcd is ever actually sufficient."
