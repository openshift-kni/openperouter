#!/bin/bash
# Sets up the containerlab fabric and wires it to an OpenShift cluster.
#
# Providers (OPENPE_E2E_PROVIDER):
#   dev-scripts (default) — virtual OCP via libvirt nets toswitch1/toswitch2 + docker
#   bastion               — clab on bastion host bridges; podman by default; skip virsh
#
# Prerequisites (both):
#   - OpenPERouter + frr-k8s on the cluster
#   - KUBECONFIG set
#   - toswitch1 / toswitch2 bridges already present
#       * dev-scripts: setup_extra_networks.sh / EXTRA_NETWORK_NAMES
#       * bastion:     setup-bastion-bridges.sh
#   - containerlab installed (or curl available to install)
#
# Bastion extras:
#   CLAB_RUNTIME=podman|docker (default podman for bastion, docker for dev-scripts)
#   Worker NIC rename / static IPs via virsh are skipped; nodelink.json is written
#   with planned addresses when OPENPE_BASTION_SKIP_WORKER_NET=true (default).
#   Full worker L2 still needs lab uplink cable + manual/future worker iface config.
#
# Usage:
#   export KUBECONFIG=...
#   # virtual OCP:
#   ./openshift/e2e/setup-clab.sh
#   # bastion:
#   set -a && source openshift/e2e/bastion.env.example && set +a
#   ./openshift/e2e/setup-bastion-bridges.sh
#   ./openshift/e2e/setup-clab.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NODELINK_OUT="${SCRIPT_DIR}/nodelink.json"

PROVIDER="${OPENPE_E2E_PROVIDER:-dev-scripts}"
if [[ "${PROVIDER}" == "bastion" ]]; then
    RUNTIME="${CLAB_RUNTIME:-${OPENPE_CLAB_RUNTIME:-podman}}"
else
    RUNTIME="${CLAB_RUNTIME:-${OPENPE_CLAB_RUNTIME:-docker}}"
fi
SKIP_WORKER_NET="${OPENPE_BASTION_SKIP_WORKER_NET:-true}"

CLI="sudo ${RUNTIME}"

echo "=== OpenPE setup-clab ==="
echo "  provider=${PROVIDER} runtime=${RUNTIME}"

if ! command -v containerlab >/dev/null 2>&1 && ! command -v clab >/dev/null 2>&1; then
    echo "containerlab not found; installing it"
    command -v curl >/dev/null 2>&1 || {
        echo "curl is required to install containerlab" >&2
        exit 1
    }
    bash -c "$(curl -fsSL https://get.containerlab.dev)"
fi
CLAB_BIN="$(command -v containerlab || command -v clab)"

if [[ "${PROVIDER}" == "dev-scripts" ]]; then
    echo "=== Step 1: Disable DHCP on extra networks (libvirt) ==="
    # dev-scripts enables DHCP by default. DHCP IPs compete with our static IPs
    # and expire after 60 minutes, breaking VXLAN routing.
    for net in toswitch1 toswitch2; do
        DHCP_RANGE=$(virsh net-dumpxml "${net}" 2>/dev/null | grep '<range' | sed 's/^ *//' ) || true
        if [ -n "${DHCP_RANGE}" ]; then
            virsh net-update "${net}" delete ip-dhcp-range "${DHCP_RANGE}" --live --config 2>/dev/null && \
                echo "  ${net}: removed DHCP range" || echo "  ${net}: failed to remove DHCP range"
        else
            echo "  ${net}: no DHCP range configured"
        fi
    done
else
    echo "=== Step 1: Skip libvirt DHCP (bastion host bridges) ==="
    for br in toswitch1 toswitch2; do
        if ! ip link show "${br}" >/dev/null 2>&1; then
            echo "ERROR: bridge ${br} missing. Run setup-bastion-bridges.sh first." >&2
            exit 1
        fi
        echo "  ${br}: present"
    done
    # Refuse if lab NICs stole the default route
    for iface in "${CLAB_BASTION_LAB_IFACE_TOSWITCH1:-eth1}" "${CLAB_BASTION_LAB_IFACE_TOSWITCH2:-eth2}"; do
        if ip route show default 2>/dev/null | grep -q "dev ${iface}"; then
            echo "ERROR: default route is on ${iface}; fix mgmt (eth0) before continuing" >&2
            ip route show default >&2 || true
            exit 1
        fi
    done
fi

echo "=== Step 2: Generate peerLeaf FRR configs ==="
cd "${REPO_ROOT}/clab/tools"
go build -o generate_leaf_config/generate_leaf generate_leaf_config/common.go generate_leaf_config/generate_leaf.go
go build -o generate_leaf_config/generate_leafkind generate_leaf_config/common.go generate_leaf_config/generate_leafkind.go

rm -f ../leafA/frr.conf
./generate_leaf_config/generate_leaf \
    -leaf leafA -neighbor 192.168.1.0 -network 100.64.0.1/32 \
    -template generate_leaf_config/frr_template/frr.conf.template

rm -f ../leafB/frr.conf
./generate_leaf_config/generate_leaf \
    -leaf leafB -neighbor 192.168.1.2 -network 100.64.0.2/32 \
    -template generate_leaf_config/frr_template/frr.conf.template

rm -f ../singlecluster/leafkind1/frr.conf
./generate_leaf_config/generate_leafkind \
    -leaf singlecluster/leafkind1 -asn 64512 -spine-ip 192.168.1.4 \
    -ipv4-listen-range 192.168.11.0/24 -ipv6-listen-range 2001:db8:11::/64 \
    -isis-net 49.0001.0000.0000.0004.00 \
    -toswitch-interface toswitch1 \
    -template generate_leaf_config/frr_template/leafkind.conf.template

rm -f ../singlecluster/leafkind2/frr.conf
./generate_leaf_config/generate_leafkind \
    -leaf singlecluster/leafkind2 -asn 64513 -spine-ip 192.168.1.6 \
    -ipv4-listen-range 192.168.12.0/24 -ipv6-listen-range 2001:db8:12::/64 \
    -isis-net 49.0001.0000.0000.0005.00 \
    -toswitch-interface toswitch2 \
    -template generate_leaf_config/frr_template/leafkind.conf.template

echo "=== Step 3: Ensure container runtime (${RUNTIME}) ==="
if [[ "${RUNTIME}" == "docker" ]]; then
    sudo systemctl enable --now docker
elif [[ "${RUNTIME}" == "podman" ]]; then
    sudo systemctl enable --now podman.socket 2>/dev/null || true
else
    echo "ERROR: unsupported CLAB_RUNTIME=${RUNTIME}" >&2
    exit 1
fi

echo "=== Step 4: Deploy clab topology ==="
cd "${REPO_ROOT}"
# containerlab 0.79 + podman: --reconfigure can SEGV in destroy/ListContainers.
# Destroy explicitly first, then deploy clean.
sudo "${CLAB_BIN}" destroy --runtime "${RUNTIME}" \
    --topo "${SCRIPT_DIR}/ocp.clab.yml" --cleanup 2>/dev/null || true
if [[ "${RUNTIME}" == "podman" ]]; then
    # Remove any leftover lab containers that confuse the next deploy
    sudo podman ps -a --filter name=clab-kind --format '{{.Names}}' \
      | xargs -r sudo podman rm -f 2>/dev/null || true
fi
sudo "${CLAB_BIN}" deploy --runtime "${RUNTIME}" \
    --topo "${SCRIPT_DIR}/ocp.clab.yml"

echo "=== Step 5: Assign IPs to clab containers ==="
cd "${REPO_ROOT}/clab"
go run tools/assign_ips/assign_ips.go \
    -file "${SCRIPT_DIR}/ip_map_ocp.txt" -engine "${CLI}"

${CLI} exec clab-kind-leafkind1 ip link set dev toswitch1 mtu 1500
${CLI} exec clab-kind-leafkind2 ip link set dev toswitch2 mtu 1500

echo "=== Step 6: Run container setup scripts ==="
for c in leafA leafB leafSRV6 hostA_red hostA_blue hostA_default hostB_red hostB_blue hostSRV6_red hostSRV6_blue; do
    container="clab-kind-${c}"
    echo "Setting up container: ${c}"

    if timeout 10s ${CLI} exec "${container}" test -f /setup.sh 2>/dev/null; then
        # Avoid bash -x on the SSH tty (large output can stall/drop interactive sessions).
        # Log to a file on the bastion instead.
        setup_log="${SCRIPT_DIR}/.setup-${c}.log"
        if timeout 5m ${CLI} exec "${container}" bash /setup.sh >"${setup_log}" 2>&1; then
            echo "  ${c}: ok (log ${setup_log})"
        else
            rc=$?
            echo "Setup failed or timed out for ${container} (exit code ${rc}); last log lines:" >&2
            tail -40 "${setup_log}" >&2 || true
            exit "${rc}"
        fi
    else
        rc=$?
        if [ "${rc}" -ne 1 ]; then
            echo "Could not inspect ${container} for /setup.sh (exit code ${rc})" >&2
            exit "${rc}"
        fi
    fi
done

NODES=$(oc get nodes -l kubernetes.io/os=linux -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

node_exec() {
    local node=$1; shift
    local pod
    pod=$(oc get pods -n openshift-openperouter -l app=controller \
        --field-selector spec.nodeName="${node}" -o jsonpath='{.items[0].metadata.name}')
    oc exec -n openshift-openperouter "${pod}" -- nsenter -t 1 -m -u -i -n "$@"
}

if [[ "${PROVIDER}" == "dev-scripts" ]]; then
    echo "=== Step 7: Rename NICs + install udev rules (virsh / ostest_*) ==="
    for node in ${NODES}; do
        short_name="${node%%.*}"
        vm_name="ostest_${short_name//-/_}"
        for i in 1 2; do
            BRIDGE_MAC=$(sudo virsh domiflist "${vm_name}" 2>/dev/null | awk -v network="toswitch${i}" '$3 == network && !found { print $5; found=1 }')
            if [ -n "${BRIDGE_MAC}" ]; then
                node_exec "${node}" bash -c "
                    echo 'SUBSYSTEM==\"net\", ATTR{address}==\"${BRIDGE_MAC}\", NAME=\"toswitch${i}\"' \
                        > /etc/udev/rules.d/70-toswitch${i}.rules
                    udevadm control --reload-rules
                    IFACE=\$(ip -br link show | grep '${BRIDGE_MAC}' | awk '{print \$1}')
                    if [ -n \"\$IFACE\" ] && [ \"\$IFACE\" != \"toswitch${i}\" ]; then
                        nmcli device set \$IFACE managed no 2>/dev/null || true
                        ip link set \$IFACE down
                        ip link set \$IFACE name toswitch${i}
                        ip link set toswitch${i} up
                        echo \"  ${node}: \$IFACE -> toswitch${i}\"
                    elif [ \"\$IFACE\" = \"toswitch${i}\" ]; then
                        nmcli device set toswitch${i} managed no 2>/dev/null || true
                        echo \"  ${node}: toswitch${i} already named\"
                    else
                        echo \"  ${node}: toswitch${i} not found (MAC ${BRIDGE_MAC})\"
                    fi
                " 2>&1
            fi
        done
    done

    echo "=== Step 8: Assign static IPs on workers (IPv4 + IPv6) ==="
    NODE_INDEX=0
    NODES_JSON=""
    for node in ${NODES}; do
        TS1_V4="192.168.11.$((100 + NODE_INDEX))"
        TS2_V4="192.168.12.$((100 + NODE_INDEX))"
        TS1_V6="2001:db8:11::$((100 + NODE_INDEX))"
        TS2_V6="2001:db8:12::$((100 + NODE_INDEX))"
        NODE_INDEX=$((NODE_INDEX + 1))

        node_exec "${node}" bash -c "
            ip -4 addr flush dev toswitch1 2>/dev/null || true
            ip -4 addr add ${TS1_V4}/24 dev toswitch1
            ip -6 addr add ${TS1_V6}/64 dev toswitch1 2>/dev/null || true
            ip link set toswitch1 up

            ip -4 addr flush dev toswitch2 2>/dev/null || true
            ip -4 addr add ${TS2_V4}/24 dev toswitch2
            ip -6 addr add ${TS2_V6}/64 dev toswitch2 2>/dev/null || true
            ip link set toswitch2 up
        " 2>&1
        echo "  ${node}: ts1=${TS1_V4}+${TS1_V6}  ts2=${TS2_V4}+${TS2_V6}"

        if [ -n "${NODES_JSON}" ]; then
            NODES_JSON="${NODES_JSON},"
        fi
        NODES_JSON="${NODES_JSON}
    \"${node}\": {
      \"ipForKindLeaf\": \"${TS1_V4}\",
      \"ipForKindLeaf2\": \"${TS2_V4}\",
      \"ipv6ForKindLeaf\": \"${TS1_V6}\",
      \"ipv6ForKindLeaf2\": \"${TS2_V6}\",
      \"ifaceForKindLeaf\": \"toswitch1\",
      \"ifaceForKindLeaf2\": \"toswitch2\",
      \"leafIfaceForKindLeaf\": \"toswitch1\",
      \"leafIfaceForKindLeaf2\": \"toswitch2\"
    }"
    done
else
    echo "=== Step 7/8: Bastion — skip virsh NIC rename / worker IP push ==="
    if [[ "${SKIP_WORKER_NET}" == "true" ]]; then
        echo "  Writing planned nodelink.json (workers not configured on-node yet)."
        echo "  After lab uplink cable: configure worker secondary NICs and re-run with"
        echo "  OPENPE_BASTION_SKIP_WORKER_NET=false once worker wiring is implemented."
    fi
    NODE_INDEX=0
    NODES_JSON=""
    for node in ${NODES}; do
        TS1_V4="192.168.11.$((100 + NODE_INDEX))"
        TS2_V4="192.168.12.$((100 + NODE_INDEX))"
        TS1_V6="2001:db8:11::$((100 + NODE_INDEX))"
        TS2_V6="2001:db8:12::$((100 + NODE_INDEX))"
        NODE_INDEX=$((NODE_INDEX + 1))
        echo "  planned ${node}: ts1=${TS1_V4} ts2=${TS2_V4}"

        if [ -n "${NODES_JSON}" ]; then
            NODES_JSON="${NODES_JSON},"
        fi
        NODES_JSON="${NODES_JSON}
    \"${node}\": {
      \"ipForKindLeaf\": \"${TS1_V4}\",
      \"ipForKindLeaf2\": \"${TS2_V4}\",
      \"ipv6ForKindLeaf\": \"${TS1_V6}\",
      \"ipv6ForKindLeaf2\": \"${TS2_V6}\",
      \"ifaceForKindLeaf\": \"toswitch1\",
      \"ifaceForKindLeaf2\": \"toswitch2\",
      \"leafIfaceForKindLeaf\": \"toswitch1\",
      \"leafIfaceForKindLeaf2\": \"toswitch2\"
    }"
    done
fi

cat > "${NODELINK_OUT}" << TOPOEOF
{
  "nodes": {${NODES_JSON}
  }
}
TOPOEOF

echo ""
echo "=== Setup complete ==="
echo "Node links config: ${NODELINK_OUT}"
echo ""
cat "${NODELINK_OUT}"

if [[ "${PROVIDER}" == "bastion" ]]; then
    echo ""
    echo "Bastion notes:"
    echo "  - Fabric is up on host bridges toswitch1/toswitch2"
    echo "  - Default route must stay on eth0 (mgmt)"
    echo "  - End-to-end Baseline needs ens1f1 lab uplink + worker secondary NICs"
fi
