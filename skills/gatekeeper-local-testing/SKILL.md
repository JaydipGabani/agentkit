---
name: gatekeeper-local-testing
description: "Use when: testing local Gatekeeper changes, validating Gatekeeper PRs, reproducing Gatekeeper bugs, spinning up kind, building and deploying Gatekeeper, running e2e BATS, testing Gator CLI, creating Kubernetes test YAMLs, checking VAP/K8sNativeValidation behavior, or proving a Gatekeeper fix works before review."
argument-hint: "Describe the Gatekeeper change or issue to test"
---

# Gatekeeper Local Testing

Use this skill to turn a Gatekeeper change into a concrete local proof. The output should be a short test plan, commands run or commands to run, fixtures used, and a clear pass/fail statement tied back to the bug or feature.

Do not stop at "tests pass" when proving a behavioral fix. Include at least one direct assertion that the changed behavior is present in a cluster object, generated object, CLI output, status field, log, metric, or admission response.

## Start Here

1. Identify the changed surface from the user's request and the diff.
   - Admission webhook, audit, mutation, VAP/K8sNativeValidation, controllers, CRDs/RBAC, Helm/deploy manifests, external data, and Gator all need different proof.
   - For PR-sized validation, compare against `origin/master`.
2. State the invariant in one sentence: "This is fixed if ...".
3. Choose the smallest loop that can disprove the fix, then add CI-parity coverage if the blast radius is broader.
4. When the user asks to test cluster behavior, run the kind bootstrap path directly; this user prefers automation over an extra confirmation prompt.
5. Before creating or applying Kubernetes resources outside the automated kind script, confirm `kubectl config current-context` points at the intended local kind cluster.

## Decision Tree

- Go-only logic, API validation, controller helper, or transformation logic: run targeted `go test`, then `make native-test` when practical.
- Shared state, caches, controllers, or concurrency-sensitive paths: add `make native-race-test` or a targeted `go test -race`.
- Admission, audit, mutation, VAP/VAPB generation, certs, RBAC, CRDs, or deployment flags: use a kind cluster and deploy a locally built image.
- Helm chart behavior: use the Helm e2e path, not only `make deploy`.
- Gator verify/test/expand/bench behavior: use the no-kind Gator loop first.
- Gator policy commands that install/list/uninstall cluster policies: build Gator, deploy Gatekeeper to kind, then run `make test-gator-policy-e2e` or a targeted policy command.
- Performance-sensitive policy evaluation or webhook paths: run targeted benchmarks and consider `make benchmark-test`.

## Repository Discovery

Do not trust version numbers, matrix values, target names, or fixture paths from this skill when the checkout can answer directly. Discover mutable facts from the current repo before planning or running tests.

Use these probes as needed:

```bash
grep '^go ' go.mod
grep -R "go-version:" .github/workflows || true
awk '$1 == "KUBERNETES_VERSION" && ($2 == "?=" || $2 == ":=" || $2 == "=") {print $3; exit}' Makefile
awk '/KUBERNETES_VERSION:[[:space:]]*\[/{line=$0; sub(/.*\[/,"",line); sub(/\].*/,"",line); gsub(/[[:space:]"]/,"",line); gsub(/,/," ",line); print line; exit}' .github/workflows/workflow.yaml
awk -F: '/^[A-Za-z0-9_.-]+:/{print $1}' Makefile | sort -u | grep -E '^(native|test|e2e|docker|gator|lint|manager)'
grep -R "make .*test\|make .*e2e\|make .*gator\|make .*docker-buildx" .github/workflows || true
```

Prefer Makefile defaults for local single-version runs, workflow matrices for CI-parity runs, and command help for CLI flags. If the repo no longer has a target or fixture named in this skill, find the current equivalent with `rg` or `find` instead of editing the skill.

## Preflight

Gatekeeper's e2e recipes expect `GITHUB_WORKSPACE` to point at the repo, and the Makefile is the source of truth for tool versions it downloads.

From the repo root:

```bash
export GITHUB_WORKSPACE="$PWD"
mkdir -p "$GITHUB_WORKSPACE/bin"
export PATH="$GITHUB_WORKSPACE/bin:$PATH"
go version
docker buildx version
kubectl config current-context || true
```

Important local side effects:

- The helper script preserves clusters and deployed Gatekeeper resources by default so the user can inspect them after the run.
- Raw `make e2e-bootstrap` deletes and recreates the default kind cluster named `kind`; use it only when intentionally resetting local state.
- `make deploy` runs `patch-image` and `manifests`, which can update `config/overlays/dev/manager_image_patch.yaml`, `config/crd/bases`, and `manifest_staging`.
- After testing, check `git diff` and keep only changes that belong to the PR.

## Helper Assets

Use [kind-e2e.sh](./scripts/kind-e2e.sh) for the default automated kind loop. It creates or reuses a kind cluster, builds and loads the local image, deploys Gatekeeper, waits for controller-manager and audit pods, and optionally runs e2e tests. It does not delete the cluster or deployed resources unless cleanup is explicitly requested.

Resolve the installed skill directory once. Set `GATEKEEPER_TEST_SKILL_DIR` explicitly if the host uses another location.

```bash
if [[ -z "${GATEKEEPER_TEST_SKILL_DIR:-}" ]]; then
  for skills_home in "${AGENTS_HOME:-}" "$PWD/.github" "$PWD/.agents" "$PWD/.claude" "$HOME/.copilot" "$HOME/.agents" "$HOME/.claude"; do
    [[ -n "$skills_home" && -d "$skills_home/skills/gatekeeper-local-testing" ]] || continue
    export GATEKEEPER_TEST_SKILL_DIR="$skills_home/skills/gatekeeper-local-testing"
    break
  done
fi
test -n "${GATEKEEPER_TEST_SKILL_DIR:-}"
```

```bash
bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
```

Common overrides:

```bash
RUN_E2E=false bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
KIND_CLUSTER_NAME=gatekeeper-local RUN_E2E=false bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
RESET_KIND_CLUSTER=true RUN_E2E=false bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
CLEANUP_KIND_CLUSTER=true bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
RUN_MATRIX=true bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
BUILD_EXTERNALDATA=false ENABLE_VAP_TESTS=0 bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
```

Preservation defaults:

- `KIND_CLUSTER_NAME` defaults to `kind` for compatibility with Gatekeeper's Makefile and BATS assumptions.
- If the named cluster already exists, the helper reuses it and deploys the local Gatekeeper image into it.
- `RESET_KIND_CLUSTER=true` is the opt-in destructive path for deleting and recreating the named cluster before the run.
- `CLEANUP_KIND_CLUSTER=true` is the opt-in destructive path for deleting the named cluster after the run.
- With `RUN_MATRIX=true` and no explicit `KIND_CLUSTER_NAME`, the helper uses one preserved cluster per discovered Kubernetes version, named `gatekeeper-k8s-<version>`.

Use [gator-local.sh](./scripts/gator-local.sh) for the no-kind Gator loop. It builds Gator, runs the local Gator test targets, and checks K8sNativeValidation failure-policy flag validation.

```bash
bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/gator-local.sh"
RUN_BENCH=true bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/gator-local.sh"
RUN_CONTAINERIZED=true bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/gator-local.sh"
```

Use these YAML fixtures for manual VAP/K8sNativeValidation proof when a fast reusable repro is enough:

- [k8snativevalidation-required-labels-template.yaml](./assets/k8snativevalidation-required-labels-template.yaml)
- [k8snativevalidation-required-labels-constraint.yaml](./assets/k8snativevalidation-required-labels-constraint.yaml)
- [good-namespace.yaml](./assets/good-namespace.yaml)
- [bad-namespace.yaml](./assets/bad-namespace.yaml)

## Fast Baseline

Run the narrowest useful tests first:

```bash
make native-test
```

Add these based on risk:

```bash
make lint
make native-race-test
make native-bench-test
make manager
```

For targeted Go tests, prefer package-level commands before the full suite:

```bash
go test ./pkg/drivers/k8scel/...
go test ./pkg/controller/constrainttemplate/...
go test -race ./pkg/gator/policy/...
```

## Gator Without Kind

Use this for changes under `cmd/gator`, `pkg/gator`, policy parsing, `gator verify`, `gator test`, `gator expand`, `gator bench`, and K8sNativeValidation shift-left behavior.

Default automated path:

```bash
bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/gator-local.sh"
```

```bash
make gator
make test-gator-verify
make test-gator-test
make test-gator-expand
make test-gator-policy
```

Run all non-containerized Gator tests:

```bash
make test-gator
```

CI also runs a containerized Gator test because some OCI tests need a registry:

```bash
make test-gator-containerized
```

Useful direct commands that discover fixtures from the current checkout:

```bash
suite="$(find test -path '*/suite.yaml' -print | head -n 1)"
./bin/gator verify "$suite" --verbose

bench_root="$(find test -type d -path '*/gator/bench' -print | head -n 1)"
for bench_dir in "$bench_root"/*/; do
  bench_name="$(basename "$bench_dir")"
  engine=rego
  case "$bench_name" in cel) engine=cel ;; both) engine=all ;; esac
  ./bin/gator bench --filename "$bench_dir" --iterations "${BENCH_ITERATIONS:-50}" --engine "$engine" --output table
done
```

For K8sNativeValidation failure-policy work, exercise default, override, and invalid inputs explicitly:

```bash
suite="$(find test -path '*/suite.yaml' -print | head -n 1)"
./bin/gator verify "$suite" --default-k8s-native-validation-failure-policy=Fail
./bin/gator verify "$suite" --default-k8s-native-validation-failure-policy=Ignore
./bin/gator verify "$suite" --default-k8s-native-validation-failure-policy=Unsupported
```

The invalid value should fail loudly. If it succeeds, the validation path is not being tested.

When creating a new Gator fixture:

- Use a `Suite` file like `test/gator/verify/suite.yaml` with at least one allowed and one denied case.
- Keep templates, constraints, and objects close together.
- Run the suite once with old behavior or an inverted expectation when possible to confirm the test is not a no-op.

## Kind Cluster Loop

Use this for admission, audit, mutation, VAP/VAPB, CRDs, RBAC, controller, webhook, and deployment behavior.

Default automated path:

```bash
bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
```

Bootstrap or reuse a kind cluster. For a fast local loop, use the `KUBERNETES_VERSION` default from the Makefile. For CI parity, discover the matrix from `.github/workflows/workflow.yaml` or run the helper script with `RUN_MATRIX=true`.

```bash
export GITHUB_WORKSPACE="$PWD"
mkdir -p "$GITHUB_WORKSPACE/bin"
export PATH="$GITHUB_WORKSPACE/bin:$PATH"
make e2e-dependencies
kind get clusters | grep -Fx kind || kind create cluster --name kind --image "kindest/node:v$(awk '$1 == "KUBERNETES_VERSION" && ($2 == "?=" || $2 == ":=" || $2 == "=") {print $3; exit}' Makefile)" --wait 5m
kubectl config use-context kind-kind
```

Use raw `make e2e-bootstrap` only when intentionally deleting and recreating the default `kind` cluster.

Build, load, and deploy the local image with VAP generation enabled, matching the main CI e2e path:

```bash
make docker-buildx IMG=gatekeeper-local:dev
kind load docker-image --name kind gatekeeper-local:dev
make deploy \
  IMG=gatekeeper-local:dev \
  USE_LOCAL_IMG=true \
  GENERATE_VAP=true \
  GENERATE_VAPBINDING=true \
  SYNC_VAP_ENFORCEMENT_SCOPE=true \
  LOG_LEVEL=DEBUG
kubectl -n gatekeeper-system wait --for=condition=Ready pod -l control-plane=controller-manager --timeout=120s
kubectl -n gatekeeper-system wait --for=condition=Ready pod -l control-plane=audit-controller --timeout=120s
```

Run e2e with VAP tests:

```bash
make test-e2e ENABLE_VAP_TESTS=1
```

For closer CI parity, include the dummy external data provider before e2e:

```bash
make e2e-build-load-externaldata-image
make test-e2e ENABLE_VAP_TESTS=1
```

To test the CI matrix locally, either run `RUN_MATRIX=true bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"` or repeat the preserved cluster setup, build/load, deploy, and `make test-e2e` for each Kubernetes version discovered from the workflow matrix.

## Helm E2E Loop

Use this when the change touches `cmd/build/helmify`, `manifest_staging/charts`, `charts`, values, chart README, CRD packaging, or chart-rendered flags.

```bash
export GITHUB_WORKSPACE="$PWD"
mkdir -p "$GITHUB_WORKSPACE/bin"
export PATH="$GITHUB_WORKSPACE/bin:$PATH"
make e2e-dependencies
kind get clusters | grep -Fx kind || kind create cluster --name kind --image "kindest/node:v$(awk '$1 == "KUBERNETES_VERSION" && ($2 == "?=" || $2 == ":=" || $2 == "=") {print $3; exit}' Makefile)" --wait 5m
kubectl config use-context kind-kind
make docker-buildx IMG=gatekeeper-e2e:latest
make docker-buildx-crds CRD_IMG=gatekeeper-crds:latest CI=true
make e2e-build-load-externaldata-image
kind load docker-image --name kind gatekeeper-e2e:latest gatekeeper-crds:latest
make e2e-helm-deploy \
  HELM_REPO=gatekeeper-e2e \
  HELM_CRD_REPO=gatekeeper-crds \
  HELM_RELEASE=latest \
  GATEKEEPER_NAMESPACE=gatekeeper-system \
  GENERATE_VAP=true \
  GENERATE_VAPBINDING=true \
  SYNC_VAP_ENFORCEMENT_SCOPE=true \
  LOG_LEVEL=DEBUG
make test-e2e GATEKEEPER_NAMESPACE=gatekeeper-system ENABLE_VAP_TESTS=1
```

For namespace-sensitive chart changes, also test `GATEKEEPER_NAMESPACE=custom-namespace`, matching CI.

## Gator Policy With Kind

Use this for `gator policy` commands that interact with a cluster.

```bash
make gator
make docker-buildx IMG=gatekeeper-e2e:latest
kind load docker-image --name kind gatekeeper-e2e:latest
make deploy IMG=gatekeeper-e2e:latest USE_LOCAL_IMG=true
kubectl -n gatekeeper-system wait --for=condition=Ready pod -l control-plane=controller-manager --timeout=120s
kubectl -n gatekeeper-system wait --for=condition=Ready pod -l control-plane=audit-controller --timeout=120s
make test-gator-policy-e2e
```

For targeted manual checks:

```bash
export GATOR_CATALOG_URL="https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/44ebe8b51c0383b375406869106c13955219bcd9/catalog.yaml"
./bin/gator policy update
./bin/gator policy search labels
./bin/gator policy install k8srequiredlabels
./bin/gator policy list
./bin/gator policy uninstall k8srequiredlabels
```

## Manual Kubernetes Fixtures

Use manual YAMLs when there is not already a BATS or Go test for the issue.

For a ready-made K8sNativeValidation/VAP fixture, use the bundled files linked under **Helper Assets**.

Fixture rules:

- Put one-off YAMLs under `/tmp/gatekeeper-local-test-*` or another scratch path.
- If the fixture should become a regression test, add it under `test/bats/tests/` using existing directories: `templates`, `constraints`, `good`, `bad`, `mutations`, and related folders.
- Add `metadata.labels.gatekeeper.sh/tests: yes` to test templates, constraints, and resources when they live in the BATS cleanup path.
- Always create both a positive resource that should pass and a negative resource that should fail or warn.
- Wait for `ConstraintTemplate` status before applying constraints or asserting admission behavior.

Common manual sequence:

```bash
kubectl apply -f /tmp/gatekeeper-local-test/template.yaml
kubectl wait --for=condition=Established --timeout=60s crd/<constraint-plural>.constraints.gatekeeper.sh
kubectl get constrainttemplate <template-name> -o json | jq '.status.byPod'
kubectl apply -f /tmp/gatekeeper-local-test/constraint.yaml
kubectl apply -f /tmp/gatekeeper-local-test/good.yaml
kubectl apply -f /tmp/gatekeeper-local-test/bad.yaml
```

For expected deny behavior, capture and assert the failed command output:

```bash
kubectl apply -f /tmp/gatekeeper-local-test/bad.yaml 2>&1 | tee /tmp/gatekeeper-local-test/bad.out
grep -E 'denied|Warning|violation' /tmp/gatekeeper-local-test/bad.out
```

Leave manual resources in place when the user wants to inspect the cluster after the proof. When cleanup is explicitly requested, delete in reverse dependency order.

## VAP And K8sNativeValidation Checks

For VAP generation changes, use existing VAP e2e fixtures first. Discover them from the current checkout instead of assuming paths:

```bash
vap_template="$(find test -path '*templates*' -name '*vap*.yaml' -print | head -n 1)"
vap_constraint="$(find test -path '*constraints*' -name '*vap*.yaml' -print | head -n 1)"
kubectl apply -f "$vap_template"
template_name="$(kubectl get -f "$vap_template" -o jsonpath='{.metadata.name}')"
kubectl get constrainttemplates.templates.gatekeeper.sh "$template_name" -o yaml
kubectl get validatingadmissionpolicy "gatekeeper-$template_name" -o yaml
kubectl apply -f "$vap_constraint"
kubectl get validatingadmissionpolicybinding -o yaml
```

Prove generated fields directly with `jsonpath` or `jq`:

```bash
kubectl get validatingadmissionpolicy "gatekeeper-$template_name" -o jsonpath='{.spec.failurePolicy}{"\n"}'
kubectl get validatingadmissionpolicy "gatekeeper-$template_name" -o json | jq '.spec.matchConditions, .spec.matchConstraints.namespaceSelector'
```

For default K8sNativeValidation failure policy specifically:

- Use a template whose `K8sNativeValidation` source omits `failurePolicy`.
- Confirm generated `ValidatingAdmissionPolicy.spec.failurePolicy` is the expected default.
- Confirm Gator commands accept `--default-k8s-native-validation-failure-policy=Fail` and `Ignore` and reject invalid values.
- If testing a runtime flag override that `make deploy` does not expose, add the flag to both controller-manager and audit deployments, then restart and assert the generated VAP value.
- Prefer testing chart wiring through Helm when the change is a Helm value.

Patch a running dev deployment only for throwaway manual validation:

```bash
kubectl -n gatekeeper-system patch deployment gatekeeper-controller-manager --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--default-k8s-native-validation-failure-policy=Ignore"}]'
kubectl -n gatekeeper-system patch deployment gatekeeper-audit --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--default-k8s-native-validation-failure-policy=Ignore"}]'
kubectl -n gatekeeper-system rollout status deployment/gatekeeper-controller-manager --timeout=120s
kubectl -n gatekeeper-system rollout status deployment/gatekeeper-audit --timeout=120s
```

After changing runtime flags that affect generated objects, delete and recreate the template or trigger reconciliation before asserting the generated VAP.

## Diagnostics

Use these when e2e or manual checks fail:

```bash
kubectl -n gatekeeper-system get pods -o wide
kubectl -n gatekeeper-system describe pod -l control-plane=controller-manager
kubectl -n gatekeeper-system logs -l control-plane=controller-manager --tail=-1
kubectl -n gatekeeper-system logs -l control-plane=audit-controller --tail=-1
kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io gatekeeper-validating-webhook-configuration -o yaml
kubectl get constrainttemplates.templates.gatekeeper.sh -o yaml
kubectl get constraints --all-namespaces 2>/dev/null || true
```

For VAP availability:

```bash
kubectl api-resources | grep -i validatingadmission
kubectl get validatingadmissionpolicies.admissionregistration.k8s.io
kubectl get validatingadmissionpolicybindings.admissionregistration.k8s.io
```

For metrics checks, follow the e2e pattern: run a temporary curl pod and curl the audit pod metrics endpoint.

## Cleanup

Cleanup is opt-in. Do not delete kind clusters, Gatekeeper deployments, generated VAP/VAPB resources, constraints, templates, or test objects at the end of a run unless the user explicitly asks for cleanup. Instead, report the active context and the key resources to inspect.

To ask the helper to clean up its cluster after a run:

```bash
CLEANUP_KIND_CLUSTER=true bash "$GATEKEEPER_TEST_SKILL_DIR/scripts/kind-e2e.sh"
```

When the user does ask for cleanup, use the relevant commands below.

For a dev overlay install:

```bash
make uninstall IMG=gatekeeper-local:dev || true
kind delete cluster --name kind
```

For manual YAMLs, delete resources in reverse order and confirm no test constraints remain:

```bash
kubectl delete "$(kubectl api-resources --api-group=constraints.gatekeeper.sh -o name | tr "\n" "," | sed -e 's/,$//')" -l gatekeeper.sh/tests=yes || true
kubectl delete constrainttemplates -l gatekeeper.sh/tests=yes || true
```

## CI Mapping

- Unit workflow: `make native-test`, `make native-race-test`, `make native-bench-test`.
- Lint workflow: `make lint`.
- Main e2e workflow: CI uses `make e2e-bootstrap` for a fresh cluster, then `make docker-buildx`, `make e2e-build-load-externaldata-image`, `kind load docker-image`, `make deploy`, and `make test-e2e ENABLE_VAP_TESTS=1`. For local verification, prefer the preserving helper unless the user explicitly asks for a fresh cluster.
- Helm e2e workflow: build Gatekeeper and CRD images, load both into kind, `make e2e-helm-deploy`, then `make test-e2e`.
- Gator workflow: `make test-gator-containerized`, plus `make gator` and direct `./bin/gator bench ...` commands.
- Gator policy workflow: `go test -cover -race ./pkg/gator/policy/...`, deploy Gatekeeper to kind, then `make test-gator-policy-e2e`.

## Completion Checklist

- The selected test would fail without the fix, or the report explains why the proof is observational.
- At least one allow path and one deny/error/warn path were exercised for policy behavior.
- Generated Kubernetes objects were checked with `jsonpath` or `jq` for the exact changed fields.
- Gatekeeper controller-manager and audit pods are ready after deployment.
- Logs do not show panics, startup validation failures, or reconciliation loops related to the change.
- Gator behavior matches cluster behavior when the same policy path is supported in both places.
- The cluster and resources are preserved for inspection unless the user explicitly requested cleanup.
- The final report includes the kind cluster/context name, namespace, and key objects to inspect.
- Any dirty generated files are intentional and understood.
