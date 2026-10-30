#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Run e2e tests ==="

pushd "$SCRIPT_DIR"/../..

# Export the ginkgo JSON report and the per-failure K8sReporter dumps (openperouter and
# frr-k8s pod logs + CR state) so CI failures are triageable. Prow exposes $ARTIFACT_DIR;
# fall back to the Makefile default for local runs. The reporter writes during the run, so
# the data survives even when the suite fails.
EXPORT_LOGS_DIR="${ARTIFACT_DIR:-/tmp/kind_logs}"

# Capture the containerlab fabric state (container inventory, leaf and spine FRR
# and network state, container logs) next to the reporter output, so it is archived
# together with it. EXIT trap so the capture also runs when the test suite fails.
FABRIC_INSPECT="${SCRIPT_DIR}/../../tools/inspect/inspect_fabric"
trap '"$FABRIC_INSPECT" --dest-dir="${EXPORT_LOGS_DIR}/clab-fabric" --container-runtime=docker || true' EXIT

CONTAINER_RUNTIME=docker make e2etests \
	KIND_EXPORT_LOGS="$EXPORT_LOGS_DIR" \
	TEST_ARGS="--nodelink-config=$SCRIPT_DIR/nodelink.json \
		--frrk8s-namespace=openshift-frr-k8s \
		--openperouter-namespace=openshift-openperouter" \
	KUBECONFIG_PATH=$KUBECONFIG \
	GINKGO_ARGS="--junit-report=junit_e2e.xml \
		--label-filter=\!'systemd-mode' \
        --focus='Single.Session.Baseline' \
		--skip='editing.the.underlay.parameters|auto-recover.when.the.named.netns.is.deleted|Webhook|Unnumbered|Router.Host.configuration|DHCP'"

popd
