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

echo "=== Run e2e tests ==="
echo "  CONTAINER_RUNTIME=${RUNTIME} KUBECONFIG=${KUBECONFIG:-}"

pushd "$SCRIPT_DIR"/../..

CONTAINER_RUNTIME="${RUNTIME}" make e2etests \
	TEST_ARGS="--nodelink-config=$SCRIPT_DIR/nodelink.json \
		--frrk8s-namespace=openshift-frr-k8s \
		--openperouter-namespace=openshift-openperouter" \
	KUBECONFIG_PATH=$KUBECONFIG \
	GINKGO_ARGS="--label-filter=\!'systemd-mode' \
        --focus='Single.Session.Baseline' \
		--skip='editing.the.underlay.parameters|auto-recover.when.the.named.netns.is.deleted|Webhook|Unnumbered|Router.Host.configuration|DHCP'"

popd
