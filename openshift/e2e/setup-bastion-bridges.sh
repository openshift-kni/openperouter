#!/usr/bin/env bash
# Bastion-only helper: create toswitch1/toswitch2 Linux bridges for ocp.clab.yml
# and optionally attach lab NICs. Does NOT change eth0 / default route.
#
# Cluster 7 map (tagging on hypervisor; guest sees untagged NICs):
#   VLAN 101 → bastion eth1 → toswitch1 (leafkind1)
#   VLAN 177 → bastion eth2 → toswitch2 (leafkind2)
#
# Usage:
#   set -a && source openshift/e2e/bastion.env.example && set +a
#   ./openshift/e2e/setup-bastion-bridges.sh
#
# Safety:
#   - Never adds a gateway on lab ifaces
#   - Flushes addresses on lab ifaces before enslaving
#   - Leaves eth0 alone
set -euo pipefail

# Prefer shared CLAB_* vars; fall back to OPENPE_* then defaults.
IFACE_TS1="${CLAB_BASTION_LAB_IFACE_TOSWITCH1:-${CLAB_BASTION_LAB_IFACE:-${OPENPE_BASTION_LAB_IFACE:-eth1}}}"
IFACE_TS2="${CLAB_BASTION_LAB_IFACE_TOSWITCH2:-eth2}"
ATTACH_LAB="${CLAB_BASTION_ATTACH_LAB_IFACE:-${OPENPE_BASTION_ATTACH_LAB_IFACE:-true}}"

echo "=== Bastion bridges for ocp.clab.yml ==="
echo "  map: ${IFACE_TS1} -> toswitch1 (VLAN 101), ${IFACE_TS2} -> toswitch2 (VLAN 177)"

refuse_if_default_on() {
  local iface="$1"
  if ip route show default 2>/dev/null | grep -q "dev ${iface}"; then
    echo "ERROR: default route is on ${iface}. Fix mgmt (eth0) first; refusing to continue." >&2
    ip route show default >&2 || true
    exit 1
  fi
}

refuse_if_default_on "${IFACE_TS1}"
if ip link show "${IFACE_TS2}" >/dev/null 2>&1; then
  refuse_if_default_on "${IFACE_TS2}"
fi

for br in toswitch1 toswitch2; do
  if ! ip link show "${br}" >/dev/null 2>&1; then
    sudo ip link add "${br}" type bridge
    echo "  created ${br}"
  else
    echo "  ${br} already exists"
  fi
  sudo ip link set "${br}" up
done

attach_to_bridge() {
  local iface="$1" br="$2"
  if ! ip link show "${iface}" >/dev/null 2>&1; then
    echo "ERROR: lab iface ${iface} not found (attach virtio NIC on HV first)" >&2
    exit 1
  fi
  sudo ip addr flush dev "${iface}" 2>/dev/null || true
  sudo ip link set "${iface}" nomaster 2>/dev/null || true
  sudo ip link set "${iface}" master "${br}"
  sudo ip link set "${iface}" up
  echo "  ${iface} -> ${br} (no address; no gateway)"
}

if [[ "${ATTACH_LAB}" == "true" ]]; then
  attach_to_bridge "${IFACE_TS1}" toswitch1
  attach_to_bridge "${IFACE_TS2}" toswitch2
fi

echo "=== Verify default still on mgmt ==="
ip route show default
refuse_if_default_on "${IFACE_TS1}"
if ip link show "${IFACE_TS2}" >/dev/null 2>&1; then
  refuse_if_default_on "${IFACE_TS2}"
fi

bridge link | grep -E "toswitch|${IFACE_TS1}|${IFACE_TS2}" || true
echo "Bastion bridges ready."
