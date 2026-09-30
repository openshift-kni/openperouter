#!/usr/bin/env bash
# Bastion bring-up for OpenPE e2e (real cluster + clab on this host).
# Does NOT run KIND (make deploy). OpenPE operator + OpenPERouter CR must exist.
# Enables CNO FRR (frr-k8s) by default — not a cluster default.
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

# CNO FRR / frr-k8s is required by host-session e2e and is not enabled by default.
DEPLOY_FRRK8S="${OPENPE_E2E_DEPLOY_FRRK8S:-true}"
OPENPE_NS="${OPENPE_E2E_NAMESPACE:-openshift-openperouter}"

echo "=== deploy-bastion ==="
echo "  KUBECONFIG=${KUBECONFIG}"
echo "  OPENPE_E2E_PROVIDER=${OPENPE_E2E_PROVIDER}"
echo "  CLAB_EXECUTOR=${CLAB_EXECUTOR} CLAB_RUNTIME=${CLAB_RUNTIME}"
echo "  OPENPE_E2E_DEPLOY_FRRK8S=${DEPLOY_FRRK8S}"
echo "  openperouter-namespace=${OPENPE_NS}"

oc get nodes >/dev/null

if [[ "${DEPLOY_FRRK8S}" == "true" ]]; then
  bash "${SCRIPT_DIR}/deploy_frrk8s.sh"
else
  echo "Skipping frr-k8s deploy (OPENPE_E2E_DEPLOY_FRRK8S=${DEPLOY_FRRK8S})"
  oc get ns "${FRRK8S_NAMESPACE:-openshift-frr-k8s}" >/dev/null || {
    echo "ERROR: openshift-frr-k8s missing; set OPENPE_E2E_DEPLOY_FRRK8S=true or enable CNO FRR first" >&2
    exit 1
  }
fi

oc get ns "${OPENPE_NS}" >/dev/null || {
  echo "ERROR: ${OPENPE_NS} missing — install OpenPE operator + OpenPERouter CR first" >&2
  exit 1
}

bash "${SCRIPT_DIR}/setup-bastion-bridges.sh"
bash "${SCRIPT_DIR}/setup-clab.sh"

echo "=== deploy-bastion complete ==="
echo "Next: ./openshift/e2e/run_tests.sh  (or full lifecycle: ./openshift/e2e/e2e-bastion.sh / make e2e-bastion)"
echo "Teardown only: ./openshift/e2e/teardown-clab.sh"
