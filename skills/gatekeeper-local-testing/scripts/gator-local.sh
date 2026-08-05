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

make_has_target() {
  local target="$1"
  grep -Eq "^${target}:" Makefile
}

run_make_target() {
  local target="$1"
  if make_has_target "$target"; then
    make "$target"
  else
    echo "skipping missing Makefile target: $target"
  fi
}

find_suite() {
  if [[ -n "${SUITE:-}" ]]; then
    echo "$SUITE"
    return 0
  fi
  if [[ -f test/gator/verify/suite.yaml ]]; then
    echo test/gator/verify/suite.yaml
    return 0
  fi
  find test -path '*/suite.yaml' -print 2>/dev/null | head -n 1
}

RUN_BENCH="${RUN_BENCH:-false}"
RUN_CONTAINERIZED="${RUN_CONTAINERIZED:-false}"
SUITE="$(find_suite)"

echo "Building Gator"
if make_has_target gator; then
  make gator
elif [[ -d cmd/gator ]]; then
  mkdir -p bin
  go build -o bin/gator ./cmd/gator
else
  echo "could not find a Gator build target or cmd/gator" >&2
  exit 1
fi

echo "Running Gator make targets"
if make_has_target test-gator; then
  make test-gator
else
  while IFS= read -r target; do
    run_make_target "$target"
  done < <(awk -F: '/^test-gator-[A-Za-z0-9_.-]+:/ {print $1}' Makefile | grep -Ev 'containerized|policy-e2e' | sort -u)
fi

if [[ -n "$SUITE" && -f "$SUITE" ]] && ./bin/gator verify --help | grep -q -- '--default-k8s-native-validation-failure-policy'; then
  echo "Checking K8sNativeValidation default failure policy flags with $SUITE"
  ./bin/gator verify "$SUITE" --default-k8s-native-validation-failure-policy=Fail
  ./bin/gator verify "$SUITE" --default-k8s-native-validation-failure-policy=Ignore

  invalid_output="${TMPDIR:-/tmp}/gator-invalid-failure-policy.out"
  if ./bin/gator verify "$SUITE" --default-k8s-native-validation-failure-policy=Unsupported >"$invalid_output" 2>&1; then
    echo "expected invalid default failure policy to fail" >&2
    cat "$invalid_output" >&2
    exit 1
  fi
  cat "$invalid_output"
else
  echo "skipping K8sNativeValidation failure-policy flag check; suite or flag not found"
fi

if [[ "$RUN_BENCH" == "true" ]]; then
  if [[ -d test/gator/bench ]]; then
    echo "Running Gator bench smoke tests"
    while IFS= read -r -d '' bench_dir; do
      bench_name="$(basename "$bench_dir")"
      engine=rego
      case "$bench_name" in
        cel) engine=cel ;;
        both) engine=all ;;
      esac
      ./bin/gator bench --filename "$bench_dir" --iterations "${BENCH_ITERATIONS:-50}" --engine "$engine" --output table
    done < <(find test/gator/bench -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  else
    echo "skipping bench smoke tests; test/gator/bench not found"
  fi
fi

if [[ "$RUN_CONTAINERIZED" == "true" ]]; then
  echo "Running containerized Gator tests"
  run_make_target test-gator-containerized
fi

echo "Gator local loop completed"
