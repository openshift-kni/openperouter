#!/bin/bash
set -euo pipefail
set -x
CURRENT_PATH=$(dirname "$0")

source "${CURRENT_PATH}/../../common.sh"

DEMO_MODE=true make deploy-multi

install_kubevirt() {
    local kubeconfig="$1"

    echo "Installing KubeVirt using kubeconfig: ${kubeconfig}"

    KUBECONFIG="$kubeconfig" kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/v1.6.2/kubevirt-operator.yaml
    KUBECONFIG="$kubeconfig" kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/v1.6.2/kubevirt-cr.yaml

    # Patch KubeVirt to allow scheduling on control-planes, so we can test live migration between two nodes
    KUBECONFIG="$kubeconfig" kubectl patch -n kubevirt kubevirt kubevirt --type merge --patch '{"spec": {"workloads": {"nodePlacement": {"tolerations": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}}}}'

    # Enable the decentralized live migration feature gate (requirement for cross cluster live migration)
    KUBECONFIG="$kubeconfig" kubectl patch -n kubevirt kubevirt kubevirt --type merge --patch '{"spec": {"configuration": {"developerConfiguration": {"featureGates": [ "DecentralizedLiveMigration" ]}}}}'

    KUBECONFIG="$kubeconfig" kubectl wait --for=condition=Available kubevirt/kubevirt -n kubevirt --timeout=10m
}

apply_demo_manifests() {
    local kubeconfig="$1"
    local manifests=("${@:2}")

    echo "Applying demo manifests using kubeconfig: ${kubeconfig}"

    export KUBECONFIG="$kubeconfig"
    apply_manifests_with_retries "${manifests[@]}"
}

for kubeconfig in $(pwd)/bin/kubeconfig-*; do
    if [[ -f "$kubeconfig" ]]; then
        cluster_name=$(basename "$kubeconfig" | sed 's/kubeconfig-//')

        install_kubevirt "$kubeconfig"

        case "$cluster_name" in
            "pe-kind-a")
                apply_demo_manifests "$kubeconfig" "cluster-a-openpe.yaml" "cluster-a-workload.yaml"
                ;;
            "pe-kind-b")
                apply_demo_manifests "$kubeconfig" "cluster-b-openpe.yaml" "cluster-b-workload.yaml"
                ;;
            *)
                echo "Unknown cluster: $cluster_name, skipping manifest application..."
                continue
                ;;
        esac
    fi
done
