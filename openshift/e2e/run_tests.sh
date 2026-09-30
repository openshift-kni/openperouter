#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bastion: clab is deployed with sudo podman (rootful). Ginkgo uses
# CONTAINER_RUNTIME as a single binary — default to podman-root.sh so tests
# see the same containers. KIND / virtual OCP keep docker unless overridden.
if [[ "${OPENPE_E2E_PROVIDER:-}" == "bastion" ]]; then
	RUNTIME="${CONTAINER_RUNTIME:-${SCRIPT_DIR}/podman-root.sh}"
else
	RUNTIME="${CONTAINER_RUNTIME:-${CLAB_RUNTIME:-${OPENPE_CLAB_RUNTIME:-docker}}}"
fi

# Namespace where OpenPERouter runs (OCP CI: openshift-openperouter; some labs: openperouter-system)
OPENPE_NS="${OPENPE_E2E_NAMESPACE:-openshift-openperouter}"

# Ginkgo --focus regex. Override with OPENPE_E2E_FOCUS to widen/narrow.
# Default: Baseline + next bastion-safe wave (no SRv6 / DHCP / webhooks).
FOCUS="${OPENPE_E2E_FOCUS:-Single.Session.Baseline|Node.Router.Status|Router.BGP.sessions|North/south.traffic.after.FRR}"
SKIP="${OPENPE_E2E_SKIP:-editing.the.underlay.parameters|auto-recover.when.the.named.netns.is.deleted|Webhook|Unnumbered|Router.Host.configuration|DHCP|SRV6}"

echo "=== Run e2e tests ==="
echo "  CONTAINER_RUNTIME=${RUNTIME} KUBECONFIG=${KUBECONFIG:-}"
echo "  openperouter-namespace=${OPENPE_NS}"
echo "  focus=${FOCUS}"
echo "  skip=${SKIP}"

pushd "$SCRIPT_DIR"/../..

CONTAINER_RUNTIME="${RUNTIME}" make e2etests \
	TEST_ARGS="--nodelink-config=$SCRIPT_DIR/nodelink.json \
		--frrk8s-namespace=openshift-frr-k8s \
		--openperouter-namespace=${OPENPE_NS}" \
	KUBECONFIG_PATH=$KUBECONFIG \
	GINKGO_ARGS="--label-filter=\!'systemd-mode' \
        --focus='${FOCUS}' \
		--skip='${SKIP}'"

popd
