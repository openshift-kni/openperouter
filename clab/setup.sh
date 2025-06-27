#!/bin/bash
set -euo pipefail
set -x

pushd "$(dirname $(readlink -f $0))"
source common.sh

generate_leaf_configs() {
    echo "Generating leaf configurations..."
    pushd tools

    REDISTRIBUTE_FLAG=""
    if [[ "${DEMO_MODE:-false}" == "true" ]]; then
        REDISTRIBUTE_FLAG="-redistribute-connected-from-vrfs"
    fi

    # leafA neighbors with spine at 192.168.1.0 and advertises 100.64.0.1/32
    go run generate_config.go -leaf leafA -neighbor 192.168.1.0 -network 100.64.0.1/32 $REDISTRIBUTE_FLAG

    # leafB neighbors with spine at 192.168.1.2 and advertises 100.64.0.2/32
    go run generate_config.go -leaf leafB -neighbor 192.168.1.2 -network 100.64.0.2/32 $REDISTRIBUTE_FLAG

    popd
}

clusters=$(${KIND_COMMAND} get clusters)
for cluster in $clusters; do
  if [[ $cluster == "$KIND_CLUSTER_NAME" ]]; then
    echo "Cluster ${KIND_CLUSTER_NAME} already exists"
    exit 0
  fi
done

if [[ ! -d "/sys/class/net/leafkind-switch" ]]; then
	sudo ip link add name leafkind-switch type bridge
fi

if [[ $(cat /sys/class/net/leafkind-switch/operstate) != "up" ]]; then
sudo ip link set dev leafkind-switch up
fi

# create registry container unless it already exists
running="$($CONTAINER_ENGINE inspect -f '{{.State.Running}}' "kind-registry" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  $CONTAINER_ENGINE run \
    -d --restart=always -p "5000:5000" --name "kind-registry" \
    registry:2
fi

generate_leaf_configs

if [[ $CONTAINER_ENGINE == "docker" ]]; then
    docker run --rm --privileged \
    --network host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/run/netns:/var/run/netns \
    -v /etc/hosts:/etc/hosts \
    -v /var/lib/docker/containers:/var/lib/docker/containers \
    --pid="host" \
    -v $(pwd):$(pwd) \
    -w $(pwd) \
    ghcr.io/srl-labs/clab:0.67.0 /usr/bin/clab deploy --reconfigure --topo kind.clab.yml
else
    # We werent able to run clab with podman in podman, installing it and running it
    # from the host.
    if ! command -v clab >/dev/null 2>&1; then
	echo "Clab is not installed, please install it first following https://containerlab.dev/install/"
	exit 1
    fi
    sudo clab deploy --reconfigure --topo kind.clab.yml $RUNTIME_OPTION
fi

load_image_to_kind quay.io/frrouting/frr:9.1.0 frr9
load_image_to_kind quay.io/frrouting/frr:10.2.1 frr10
load_image_to_kind gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1 rbacproxy
load_image_to_kind quay.io/metallb/frr-k8s:v0.0.17 frrk8s

${KIND_COMMAND} --name ${KIND_CLUSTER_NAME} get kubeconfig > $KUBECONFIG_PATH
export KUBECONFIG=$KUBECONFIG_PATH

# connect the registry to the cluster network
$CONTAINER_ENGINE network connect "kind" "kind-registry" || true

# Document the local registry
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
kubectl apply -f kind-registry_configmap.yaml

kind/frr-k8s/setup.sh

sudo $(which go) run tools/assign_ips.go -file ip_map.txt -engine ${CONTAINER_ENGINE}

${CONTAINER_ENGINE_CLI} exec clab-kind-leafA /setup.sh
${CONTAINER_ENGINE_CLI} exec clab-kind-leafB /setup.sh
${CONTAINER_ENGINE_CLI} exec clab-kind-hostA_red /setup.sh
${CONTAINER_ENGINE_CLI} exec clab-kind-hostA_blue /setup.sh
${CONTAINER_ENGINE_CLI} exec clab-kind-hostB_red /setup.sh
${CONTAINER_ENGINE_CLI} exec clab-kind-hostB_blue /setup.sh

if ! pgrep -f check_veths.sh | xargs -r ps -p | grep -q pe-kind-control-plane; then
	sudo -E ./check_veths.sh kindctrlpl:toswitch:pe-kind-control-plane:192.168.11.3/24  kindworker:toswitch:pe-kind-worker:192.168.11.4/24 &
fi
sleep 4s

popd
