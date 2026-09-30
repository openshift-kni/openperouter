#!/usr/bin/env bash
# Reverse CNO FRR enablement if deploy_frrk8s.sh recorded that e2e enabled it.
# Force with OPENPE_E2E_TEARDOWN_FRRK8S=force even without a marker.
# Skip with OPENPE_E2E_TEARDOWN_FRRK8S=false.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.e2e-bastion-state"
MARKER="${STATE_DIR}/frrk8s-enabled-by-e2e"

TEARDOWN="${OPENPE_E2E_TEARDOWN_FRRK8S:-true}"
FRRK8S_NAMESPACE="${FRRK8S_NAMESPACE:-openshift-frr-k8s}"

echo "=== teardown-frrk8s ==="
echo "  OPENPE_E2E_TEARDOWN_FRRK8S=${TEARDOWN}"

if [[ "${TEARDOWN}" == "false" ]]; then
  echo "Skipping frr-k8s / CNO FRR teardown"
  exit 0
fi

if [[ "${TEARDOWN}" != "force" && ! -f "${MARKER}" ]]; then
  echo "No marker at ${MARKER} (FRR was already enabled before e2e); leaving CNO unchanged"
  exit 0
fi

echo "Removing CNO additionalRoutingCapabilities (FRR)"
# remove the whole field; ignore if already absent
if oc get networks.operator.openshift.io cluster -o jsonpath='{.spec.additionalRoutingCapabilities}' 2>/dev/null | grep -q .; then
  oc patch networks.operator.openshift.io cluster --type=json \
    -p='[{"op":"remove","path":"/spec/additionalRoutingCapabilities"}]' \
    || oc patch networks.operator.openshift.io cluster --type=merge \
      -p '{"spec":{"additionalRoutingCapabilities":null}}' || true
else
  echo "  additionalRoutingCapabilities already absent"
fi

echo "Waiting for frr-k8s pods to terminate (best-effort)"
# CNO may delete the operands; don't fail the whole e2e on slow cleanup
for _ in $(seq 1 60); do
  count="$(oc get pods -n "${FRRK8S_NAMESPACE}" -l app=frr-k8s --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${count}" == "0" ]]; then
    break
  fi
  sleep 5
done
oc get pods -n "${FRRK8S_NAMESPACE}" -l app=frr-k8s 2>/dev/null || true

rm -f "${MARKER}"
rmdir "${STATE_DIR}" 2>/dev/null || true

echo "=== teardown-frrk8s complete ==="
