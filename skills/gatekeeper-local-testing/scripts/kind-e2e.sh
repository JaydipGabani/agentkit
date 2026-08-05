#!/usr/bin/env bash
set -euo pipefail

repo_root="${REPO_ROOT:-$PWD}"
cd "$repo_root"

if [[ ! -f Makefile || ! -f go.mod ]]; then
  echo "run from the Gatekeeper repo root, or set REPO_ROOT" >&2
  exit 1
fi

if ! grep -q 'module github.com/open-policy-agent/gatekeeper/v3' go.mod; then
  echo "go.mod does not look like open-policy-agent/gatekeeper" >&2
  exit 1
fi

make_var() {
  local name="$1"
  awk -v name="$name" '
    $1 == name && ($2 == "?=" || $2 == ":=" || $2 == "=") {
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' Makefile
}

workflow_kubernetes_versions() {
  local workflow=".github/workflows/workflow.yaml"
  [[ -f "$workflow" ]] || return 0
  awk '
    /KUBERNETES_VERSION:[[:space:]]*\[/ {
      line = $0
      sub(/.*\[/, "", line)
      sub(/\].*/, "", line)
      gsub(/[[:space:]"]/, "", line)
      gsub(/,/, " ", line)
      print line
      exit
    }
  ' "$workflow"
}

workflow_has() {
  local pattern="$1"
  grep -R "$pattern" .github/workflows >/dev/null 2>&1
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "could not discover $name from the current Gatekeeper checkout" >&2
    exit 1
  fi
}

export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$PWD}"
mkdir -p "$GITHUB_WORKSPACE/bin"
export PATH="$GITHUB_WORKSPACE/bin:$PATH"

default_kubernetes_version="$(make_var KUBERNETES_VERSION)"
require_value KUBERNETES_VERSION "$default_kubernetes_version"

KUBERNETES_VERSION="${KUBERNETES_VERSION:-$default_kubernetes_version}"
IMG="${IMG:-gatekeeper-local:$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"
RUN_E2E="${RUN_E2E:-true}"
REQUESTED_KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
RESET_KIND_CLUSTER="${RESET_KIND_CLUSTER:-false}"
CLEANUP_KIND_CLUSTER="${CLEANUP_KIND_CLUSTER:-false}"
ENABLE_VAP_TESTS="${ENABLE_VAP_TESTS:-$(workflow_has 'ENABLE_VAP_TESTS=1' && echo 1 || echo 0)}"
BUILD_EXTERNALDATA="${BUILD_EXTERNALDATA:-$(workflow_has 'e2e-build-load-externaldata-image' && echo true || echo false)}"
GENERATE_VAP="${GENERATE_VAP:-$(make_var GENERATE_VAP)}"
GENERATE_VAPBINDING="${GENERATE_VAPBINDING:-$(make_var GENERATE_VAPBINDING)}"
SYNC_VAP_ENFORCEMENT_SCOPE="${SYNC_VAP_ENFORCEMENT_SCOPE:-$(make_var SYNC_VAP_ENFORCEMENT_SCOPE)}"
LOG_LEVEL="${LOG_LEVEL:-$(make_var LOG_LEVEL)}"
PLATFORM="${PLATFORM:-$(make_var PLATFORM)}"
OUTPUT_TYPE="${OUTPUT_TYPE:-$(make_var OUTPUT_TYPE)}"

require_value GENERATE_VAP "$GENERATE_VAP"
require_value GENERATE_VAPBINDING "$GENERATE_VAPBINDING"
require_value SYNC_VAP_ENFORCEMENT_SCOPE "$SYNC_VAP_ENFORCEMENT_SCOPE"
require_value LOG_LEVEL "$LOG_LEVEL"
require_value PLATFORM "$PLATFORM"
require_value OUTPUT_TYPE "$OUTPUT_TYPE"

kind_cluster_exists() {
  local cluster_name="$1"
  kind get clusters 2>/dev/null | grep -Fxq "$cluster_name"
}

create_kind_cluster() {
  local kubernetes_version="$1"
  local cluster_name="$2"
  local node_image="kindest/node:v${kubernetes_version}"

  if [[ -n "${KIND_CLUSTER_FILE:-}" ]]; then
    kind create cluster --name "$cluster_name" --config "$KIND_CLUSTER_FILE" --image "$node_image" --wait 5m
  else
    kind create cluster --name "$cluster_name" --image "$node_image" --wait 5m
  fi
}

ensure_kind_cluster() {
  local kubernetes_version="$1"
  local cluster_name="$2"

  if [[ "$RESET_KIND_CLUSTER" == "true" ]]; then
    echo "RESET_KIND_CLUSTER=true: deleting kind cluster $cluster_name before recreating it"
    kind delete cluster --name "$cluster_name" || true
  fi

  if kind_cluster_exists "$cluster_name"; then
    echo "Using existing kind cluster $cluster_name. KUBERNETES_VERSION=$kubernetes_version is only used when creating a new cluster; set RESET_KIND_CLUSTER=true to recreate."
    kubectl config use-context "kind-${cluster_name}"
    return 0
  fi

  echo "Creating kind cluster $cluster_name with Kubernetes $kubernetes_version"
  create_kind_cluster "$kubernetes_version" "$cluster_name"
}

build_and_load_externaldata_image() {
  local cluster_name="$1"

  echo "Building dummy external data provider image"
  make docker-buildx-builder
  ./test/externaldata/dummy-provider/scripts/generate-tls-certificate.sh
  docker buildx build \
    --platform="$PLATFORM" \
    --output="$OUTPUT_TYPE" \
    -t dummy-provider:test \
    -f test/externaldata/dummy-provider/Dockerfile test/externaldata/dummy-provider

  echo "Loading dummy-provider:test into kind cluster $cluster_name"
  kind load docker-image --name "$cluster_name" dummy-provider:test
}

run_once() {
  local kubernetes_version="$1"
  local cluster_name="$REQUESTED_KIND_CLUSTER_NAME"

  if [[ "${RUN_MATRIX:-false}" == "true" && -z "${KIND_CLUSTER_NAME:-}" ]]; then
    cluster_name="gatekeeper-k8s-${kubernetes_version//./-}"
  fi

  echo "Installing Gatekeeper e2e dependencies"
  make e2e-dependencies "KUBERNETES_VERSION=$kubernetes_version"

  ensure_kind_cluster "$kubernetes_version" "$cluster_name"

  echo "Building Gatekeeper image $IMG"
  make docker-buildx "IMG=$IMG"

  if [[ "$BUILD_EXTERNALDATA" == "true" ]]; then
    build_and_load_externaldata_image "$cluster_name"
  fi

  echo "Loading $IMG into kind cluster $cluster_name"
  kind load docker-image --name "$cluster_name" "$IMG"

  echo "Deploying Gatekeeper from local image"
  make deploy \
    "IMG=$IMG" \
    USE_LOCAL_IMG=true \
    "GENERATE_VAP=$GENERATE_VAP" \
    "GENERATE_VAPBINDING=$GENERATE_VAPBINDING" \
    "SYNC_VAP_ENFORCEMENT_SCOPE=$SYNC_VAP_ENFORCEMENT_SCOPE" \
    "LOG_LEVEL=$LOG_LEVEL"

  kubectl -n gatekeeper-system wait --for=condition=Ready pod -l control-plane=controller-manager --timeout=120s
  kubectl -n gatekeeper-system wait --for=condition=Ready pod -l control-plane=audit-controller --timeout=120s

  if [[ "$RUN_E2E" == "true" ]]; then
    echo "Running Gatekeeper e2e tests"
    make test-e2e "KUBERNETES_VERSION=$kubernetes_version" "ENABLE_VAP_TESTS=$ENABLE_VAP_TESTS"
  fi

  if [[ "$CLEANUP_KIND_CLUSTER" == "true" ]]; then
    echo "CLEANUP_KIND_CLUSTER=true: deleting kind cluster $cluster_name"
    kind delete cluster --name "$cluster_name"
  else
    echo "Preserving kind cluster $cluster_name and deployed Gatekeeper resources for inspection"
    echo "Inspect with: kubectl config use-context kind-${cluster_name}; kubectl -n gatekeeper-system get pods"
  fi
}

versions=("$KUBERNETES_VERSION")
if [[ "${RUN_MATRIX:-false}" == "true" ]]; then
  if [[ -n "${KUBERNETES_VERSIONS:-}" ]]; then
    read -r -a versions <<<"$KUBERNETES_VERSIONS"
  else
    matrix_versions="$(workflow_kubernetes_versions)"
    if [[ -n "$matrix_versions" ]]; then
      read -r -a versions <<<"$matrix_versions"
    fi
  fi
fi

display_kind_cluster_name="${KIND_CLUSTER_NAME:-$REQUESTED_KIND_CLUSTER_NAME}"
if [[ "${RUN_MATRIX:-false}" == "true" && -z "${KIND_CLUSTER_NAME:-}" ]]; then
  display_kind_cluster_name="auto-per-version"
fi

echo "Discovered settings: KUBERNETES_VERSION=${versions[*]} IMG=$IMG KIND_CLUSTER_NAME=$display_kind_cluster_name RESET_KIND_CLUSTER=$RESET_KIND_CLUSTER CLEANUP_KIND_CLUSTER=$CLEANUP_KIND_CLUSTER ENABLE_VAP_TESTS=$ENABLE_VAP_TESTS BUILD_EXTERNALDATA=$BUILD_EXTERNALDATA"
for version in "${versions[@]}"; do
  run_once "$version"
done

echo "Gatekeeper local kind loop completed; clusters and deployed resources were preserved unless CLEANUP_KIND_CLUSTER=true was set"
