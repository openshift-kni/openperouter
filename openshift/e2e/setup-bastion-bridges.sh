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
#   - Pins NM so eth1/eth2 never autoconf / never-default (stops SSH theft)
#   - Leaves eth0 alone (expect mgmt + default only there)
set -euo pipefail

MGMT_IFACE="${CLAB_BASTION_MGMT_IFACE:-eth0}"
IFACE_TS1="${CLAB_BASTION_LAB_IFACE_TOSWITCH1:-${CLAB_BASTION_LAB_IFACE:-${OPENPE_BASTION_LAB_IFACE:-eth1}}}"
IFACE_TS2="${CLAB_BASTION_LAB_IFACE_TOSWITCH2:-eth2}"
ATTACH_LAB="${CLAB_BASTION_ATTACH_LAB_IFACE:-${OPENPE_BASTION_ATTACH_LAB_IFACE:-true}}"

echo "=== Bastion bridges for ocp.clab.yml ==="
echo "  mgmt: ${MGMT_IFACE} (SSH / default only)"
echo "  map: ${IFACE_TS1} -> toswitch1 (VLAN 101), ${IFACE_TS2} -> toswitch2 (VLAN 177)"

refuse_if_default_on() {
  local iface="$1"
  if ip route show default 2>/dev/null | grep -q "dev ${iface}"; then
    echo "ERROR: default route is on ${iface}. Fix mgmt (${MGMT_IFACE}) first; refusing to continue." >&2
    ip route show default >&2 || true
    exit 1
  fi
}

require_mgmt_ok() {
  if ! ip -br addr show "${MGMT_IFACE}" 2>/dev/null | grep -q 'UP'; then
    echo "ERROR: ${MGMT_IFACE} is not UP" >&2
    exit 1
  fi
  # ip -br does not print the word "inet"; match an IPv4 address instead.
  if ! ip -4 -br addr show "${MGMT_IFACE}" 2>/dev/null | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "ERROR: ${MGMT_IFACE} has no IPv4 address (mgmt must stay here)" >&2
    ip -br addr >&2 || true
    exit 1
  fi
  if ! ip route show default 2>/dev/null | grep -q "dev ${MGMT_IFACE}"; then
    echo "ERROR: default route is not on ${MGMT_IFACE}" >&2
    ip route show default >&2 || true
    exit 1
  fi
}

# Make NetworkManager keep lab NICs address-less forever (survives reboot).
harden_lab_nm() {
  local iface="$1"
  local con_name="lab-${iface}"

  if ! command -v nmcli >/dev/null 2>&1; then
    echo "  warn: nmcli missing; cannot persist NM harden for ${iface}"
    return 0
  fi

  # Drop any existing NM profiles bound to this iface (except we recreate lab-*)
  while read -r name; do
    [[ -z "${name}" ]] && continue
    if [[ "${name}" != "${con_name}" ]]; then
      echo "  nmcli: deleting profile '${name}' on ${iface}"
      sudo nmcli con delete "${name}" 2>/dev/null || true
    fi
  done < <(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d="${iface}" '$2==d{print $1}')

  if nmcli -t -f NAME connection show | grep -qx "${con_name}"; then
    sudo nmcli con mod "${con_name}" \
      connection.interface-name "${iface}" \
      connection.autoconnect yes \
      ipv4.method disabled \
      ipv6.method disabled \
      ipv4.never-default yes \
      ipv4.gateway "" \
      ipv6.never-default yes
  else
    sudo nmcli con add type ethernet ifname "${iface}" con-name "${con_name}" \
      connection.autoconnect yes \
      ipv4.method disabled \
      ipv6.method disabled \
      ipv4.never-default yes \
      ipv6.never-default yes
  fi
  sudo nmcli con up "${con_name}" 2>/dev/null || true
  echo "  nmcli: ${con_name} -> ${iface} (ipv4/ipv6 disabled, never-default)"
}

pin_mgmt_nm() {
  if ! command -v nmcli >/dev/null 2>&1; then
    return 0
  fi
  local mgmt_con
  mgmt_con="$(nmcli -t -f DEVICE,CONNECTION device status | awk -F: -v d="${MGMT_IFACE}" '$1==d{print $2}')"
  if [[ -z "${mgmt_con}" || "${mgmt_con}" == "--" ]]; then
    echo "  warn: no NM connection active on ${MGMT_IFACE}; skip pin"
    return 0
  fi
  # Prefer mgmt route over any stray lab profile
  sudo nmcli con mod "${mgmt_con}" \
    connection.interface-name "${MGMT_IFACE}" \
    ipv4.never-default no \
    ipv4.route-metric 50 2>/dev/null || true
  echo "  nmcli: pinned '${mgmt_con}' to ${MGMT_IFACE} (route-metric 50)"
}

require_mgmt_ok
refuse_if_default_on "${IFACE_TS1}"
if ip link show "${IFACE_TS2}" >/dev/null 2>&1; then
  refuse_if_default_on "${IFACE_TS2}"
fi

pin_mgmt_nm

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
  harden_lab_nm "${iface}"
  sudo ip addr flush dev "${iface}" 2>/dev/null || true
  sudo ip link set "${iface}" nomaster 2>/dev/null || true
  sudo ip link set "${iface}" master "${br}"
  sudo ip link set "${iface}" up
  echo "  ${iface} -> ${br} (no address; no gateway)"
}

if [[ "${ATTACH_LAB}" == "true" ]]; then
  attach_to_bridge "${IFACE_TS1}" toswitch1
  attach_to_bridge "${IFACE_TS2}" toswitch2
else
  # Still harden so DHCP/NM cannot steal SSH even when not attaching yet
  harden_lab_nm "${IFACE_TS1}"
  if ip link show "${IFACE_TS2}" >/dev/null 2>&1; then
    harden_lab_nm "${IFACE_TS2}"
  fi
fi

echo "=== Verify default still on mgmt ==="
ip route show default
require_mgmt_ok
refuse_if_default_on "${IFACE_TS1}"
if ip link show "${IFACE_TS2}" >/dev/null 2>&1; then
  refuse_if_default_on "${IFACE_TS2}"
fi

bridge link | grep -E "toswitch|${IFACE_TS1}|${IFACE_TS2}" || true
echo "Bastion bridges ready."
