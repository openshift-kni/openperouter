#!/usr/bin/env bash
# Bastion / OCP e2e lifecycle (CI entrypoint):
#   1) bridges + clab fabric   (deploy-bastion.sh → setup-clab.sh)
#   2) existing focused tests  (run_tests.sh)
#   3) tear down fabric        (teardown-clab.sh) — always, via EXIT trap
#
# This is the OCP/bastion counterpart to KIND "make deploy && make e2etests && make clean".
# It does NOT run KIND "make deploy". Operator + OpenPERouter CR must already be installed
# (CI installs operators before this job).
#
# Usage (on bastion):
#   export KUBECONFIG=/path/to/ocp/kubeconfig
#   set -a && source openshift/e2e/bastion.env.example && set +a
#   ./openshift/e2e/e2e-bastion.sh
#
#   # or: make e2e-bastion
#
# Debug: OPENPE_E2E_SKIP_TEARDOWN=true keeps the fabric after the run.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "ERROR: KUBECONFIG must be set to the target OpenShift cluster" >&2
  exit 1
fi

export OPENPE_E2E_PROVIDER="${OPENPE_E2E_PROVIDER:-bastion}"
export CLAB_EXECUTOR="${CLAB_EXECUTOR:-local}"
export CLAB_RUNTIME="${CLAB_RUNTIME:-podman}"
export OPENPE_CLAB_RUNTIME="${OPENPE_CLAB_RUNTIME:-${CLAB_RUNTIME}}"
# Ginkgo must use rootful podman (same as setup-clab's sudo podman).
export CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-${SCRIPT_DIR}/podman-root.sh}"

SKIP_TEARDOWN="${OPENPE_E2E_SKIP_TEARDOWN:-false}"
TEST_RC=0

teardown() {
  if [[ "${SKIP_TEARDOWN}" == "true" ]]; then
    echo "=== SKIP teardown (OPENPE_E2E_SKIP_TEARDOWN=true) ==="
    return 0
  fi
  echo "=== EXIT trap: teardown-clab ==="
  bash "${SCRIPT_DIR}/teardown-clab.sh" || {
    echo "ERROR: teardown-clab failed" >&2
    return 1
  }
}

trap teardown EXIT

echo "=== e2e-bastion lifecycle ==="
echo "  KUBECONFIG=${KUBECONFIG}"
echo "  OPENPE_E2E_PROVIDER=${OPENPE_E2E_PROVIDER}"
echo "  CLAB_RUNTIME=${CLAB_RUNTIME} CONTAINER_RUNTIME=${CONTAINER_RUNTIME}"
echo "  OPENPE_E2E_SKIP_TEARDOWN=${SKIP_TEARDOWN}"

bash "${SCRIPT_DIR}/deploy-bastion.sh"

set +e
bash "${SCRIPT_DIR}/run_tests.sh"
TEST_RC=$?
set -e

if [[ "${TEST_RC}" -ne 0 ]]; then
  echo "ERROR: run_tests.sh exited ${TEST_RC}" >&2
fi

# trap runs teardown; propagate test status
exit "${TEST_RC}"
