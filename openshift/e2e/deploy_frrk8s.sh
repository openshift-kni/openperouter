#!/usr/bin/env bash
# Deploy FRR-K8s through the OpenShift Cluster Network Operator.
# Idempotent: safe to re-run when additionalRoutingCapabilities is already set.
# Always records openshift/e2e/.e2e-bastion-state/frrk8s-enabled-by-e2e so
# teardown_frrk8s.sh removes CNO FRR after the bastion e2e run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.e2e-bastion-state"
MARKER="${STATE_DIR}/frrk8s-enabled-by-e2e"

FRRK8S_NAMESPACE="${FRRK8S_NAMESPACE:-openshift-frr-k8s}"
FRRK8S_SELECTOR="${FRRK8S_SELECTOR:-app=frr-k8s}"
FRRK8S_TIMEOUT="${FRRK8S_TIMEOUT:-5m}"

echo "Creating FRR-K8s namespace and debug configuration"
oc create namespace "${FRRK8S_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<EOFCM
apiVersion: v1
kind: ConfigMap
metadata:
  name: env-overrides
  namespace: ${FRRK8S_NAMESPACE}
data:
  frrk8s-loglevel: "--log-level=debug"
  frrk8s-poll-interval: "--poll-interval=5s"
EOFCM

ALREADY="$(oc get networks.operator.openshift.io cluster -o jsonpath='{.spec.additionalRoutingCapabilities.providers[*]}' 2>/dev/null || true)"
if echo " ${ALREADY} " | grep -q ' FRR '; then
  echo "CNO FRR already enabled (providers: ${ALREADY})"
else
  echo "Enabling the FRR additional routing capability in CNO"
  oc patch networks.operator.openshift.io cluster --type=merge \
    -p '{"spec":{"additionalRoutingCapabilities":{"providers":["FRR"]}}}'
fi

# Bastion e2e owns FRR for the run: always mark so teardown removes it after.
mkdir -p "${STATE_DIR}"
date -u +%Y-%m-%dT%H:%M:%SZ > "${MARKER}"
echo "Recorded ${MARKER} for post-e2e teardown"

echo "Waiting for FRR-K8s pods to be ready"
oc wait pod -n "${FRRK8S_NAMESPACE}" -l "${FRRK8S_SELECTOR}" \
    --for=create --timeout="${FRRK8S_TIMEOUT}"
oc wait pod -n "${FRRK8S_NAMESPACE}" -l "${FRRK8S_SELECTOR}" \
    --for=condition=Ready --timeout="${FRRK8S_TIMEOUT}"

echo "FRR-K8s is ready in ${FRRK8S_NAMESPACE}"
