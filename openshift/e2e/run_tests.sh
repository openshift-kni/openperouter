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

CONTAINER_RUNTIME=docker make e2etests \
	KIND_EXPORT_LOGS="$EXPORT_LOGS_DIR" \
	TEST_ARGS="--nodelink-config=$SCRIPT_DIR/nodelink.json \
		--frrk8s-namespace=openshift-frr-k8s \
		--openperouter-namespace=openshift-openperouter" \
	KUBECONFIG_PATH=$KUBECONFIG \
	GINKGO_ARGS="--junit-report=junit_e2e.xml \
		--label-filter=\!'systemd-mode && \!grout-only' \
        --focus='Single.Session.Baseline' \
	--focus='with Underlay in ipv4 should create two pods connected to the l2 overlay' \
	--focus='should allow pod-to-pod L2 connectivity without a VRF' \
	--focus='should establish pod-to-pod connectivity over L2VNI' \
	--focus='should maintain Type 2 MAC\+IP route for silent workload' \
	--focus='should maintain connectivity after pod migrates to another node' \
	--focus='should maintain stretched L2 traffic across nodes with minimal disruption when a router pod is deleted' \
	--skip='editing.the.underlay.parameters|auto-recover.when.the.named.netns.is.deleted|Webhook|Unnumbered|Router.Host.configuration|DHCP|dual stack|single stack ipv6|migrates to another node ipv6|with IPv6 VTEP'"
popd
