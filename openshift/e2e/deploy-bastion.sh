#!/usr/bin/env bash
# Bastion bring-up for OpenPE e2e (real cluster + clab on this host).
# Does NOT run KIND (make deploy). Does NOT install the operator — do that first.
#
# Usage (on bastion / CI):
#   export KUBECONFIG=/path/to/hlxcl7/auth/kubeconfig
#   set -a && source openshift/e2e/bastion.env.example && set +a
#   ./openshift/e2e/deploy-bastion.sh
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

echo "=== deploy-bastion ==="
echo "  KUBECONFIG=${KUBECONFIG}"
echo "  OPENPE_E2E_PROVIDER=${OPENPE_E2E_PROVIDER}"
echo "  CLAB_EXECUTOR=${CLAB_EXECUTOR} CLAB_RUNTIME=${CLAB_RUNTIME}"

oc get nodes >/dev/null
oc get ns openshift-openperouter >/dev/null || {
  echo "ERROR: openshift-openperouter missing — install OpenPE operator + OpenPERouter CR first" >&2
  exit 1
}

bash "${SCRIPT_DIR}/setup-bastion-bridges.sh"
bash "${SCRIPT_DIR}/setup-clab.sh"

echo "=== deploy-bastion complete ==="
echo "Next (after lab uplink + worker NICs): ./openshift/e2e/run_tests.sh"
