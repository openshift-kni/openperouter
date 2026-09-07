#!/usr/bin/env bash

set -euo pipefail

# Route external host-session traffic through node host networking.
oc patch network.operator.openshift.io cluster --type=merge \
  -p '{"spec":{"defaultNetwork":{"ovnKubernetesConfig":{"gatewayConfig":{"routingViaHost":true,"ipForwarding":"Global"}}}}}'

# Wait until CNO has reconciled the gateway configuration.
oc wait --for=condition=Available=True --timeout=10m co/network
oc wait --for=condition=Progressing=False --timeout=10m co/network
oc wait --for=condition=Degraded=False --timeout=10m co/network

oc get network.operator.openshift.io cluster \
  -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.gatewayConfig}{"\n"}'
