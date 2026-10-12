#!/usr/bin/env bash
# Apply underlay IPs on selected worker nodes for bastion e2e.
# Addresses and iface names come from nodelink.json (setup-clab.sh).
# OPENPE_UNDERLAY_IFACE / OPENPE_UNDERLAY_IFACE2 override nodelink ifaces when set.
#
# Bastion default is single-homed: leaf2 only when OPENPE_UNDERLAY_IFACE2 is set
# (same contract as DualLeafEnabled / setup-clab nodelink). Do not expect a second
# worker underlay unless that env is set and the NIC is cabled.
#
# IPv4-only: nodelink may list ipv6ForKindLeaf*; this script applies IPv4 only.
# Bastion focused e2e is IPv4 underlay today. Records state for
# teardown-bastion-worker-net.sh (and run_tests iface hydration).
#
# Idempotent: each apply flushes IPv4 on the iface then adds the planned address
# (test owns IPv4 on that NIC for the run).
#
# Tagged underlay (required when switch native-vlan != leaf VLAN): set
#   OPENPE_UNDERLAY_IFACE=ens5f0.173
#   OPENPE_UNDERLAY_IFACE2=ens5f1.174
# Never put underlay on the native VLAN (hlxcl2: native 102 strips tags → BGP fails).
# VLAN map: cl1 171/172 | cl2 173/174 | cl3 175/176 | cl7 177/178 (leaf1/leaf2).
# If iface is parent.VID and missing, create `ip link add … type vlan id VID`.
# Also flushes IPv4 on the parent so leftovers on bare ens5f* cannot steal routes.
# Teardown deletes the planned address and removes vlan subifs we recorded.
#
# Re-run after a partial apply is safe. Planned state is rewritten in full before
# the apply loop so EXIT teardown can remove addresses even if a later node fails.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODELINK="${SCRIPT_DIR}/nodelink.json"
STATE_DIR="${SCRIPT_DIR}/.e2e-bastion-state"
STATE_FILE="${STATE_DIR}/worker-net.json"

OPENPE_NS="${OPENPE_E2E_NAMESPACE:-openshift-openperouter}"

if [[ ! -f "${NODELINK}" ]]; then
  echo "ERROR: ${NODELINK} missing — run setup-clab.sh / deploy-bastion first" >&2
  exit 1
fi

if ! oc get ns "${OPENPE_NS}" >/dev/null 2>&1; then
  echo "ERROR: OpenPE namespace ${OPENPE_NS} not found" >&2
  exit 1
fi

# Bastion does not virsh-rename NICs to toswitch*; require the real worker iface.
if [[ -z "${OPENPE_UNDERLAY_IFACE:-}" ]]; then
  echo "ERROR: OPENPE_UNDERLAY_IFACE must be set on bastion (e.g. ens5f0.173)" >&2
  echo "  setup-clab does not rename worker NICs; default toswitch1 is not safe here" >&2
  exit 1
fi

echo "=== configure-bastion-worker-net ==="
echo "  namespace=${OPENPE_NS}"
echo "  nodelink=${NODELINK}"
echo "  OPENPE_UNDERLAY_IFACE=${OPENPE_UNDERLAY_IFACE}"
if [[ -n "${OPENPE_UNDERLAY_IFACE2:-}" ]]; then
  echo "  OPENPE_UNDERLAY_IFACE2=${OPENPE_UNDERLAY_IFACE2} (dual-leaf)"
else
  echo "  OPENPE_UNDERLAY_IFACE2=<unset> (leaf2 skipped)"
fi

# Same path as teardown: prefer oc debug/chroot, fall back to controller nsenter.
node_exec() {
  local node=$1; shift
  if oc debug "node/${node}" --quiet -- chroot /host "$@" ; then
    return 0
  fi
  echo "WARNING: oc debug failed on ${node}; trying controller nsenter" >&2
  local pod
  pod=$(oc get pods -n "${OPENPE_NS}" -l app=controller \
    --field-selector "spec.nodeName=${node}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "${pod}" ]]; then
    echo "ERROR: no controller on ${node} in ${OPENPE_NS}; cannot configure" >&2
    return 1
  fi
  oc exec -n "${OPENPE_NS}" "${pod}" -- nsenter -t 1 -m -u -i -n "$@"
}

# Build apply list from nodelink; env overrides iface names when set.
# Write worker-net.json via json.dump (include iface env for run_tests / Ginkgo).
export OPENPE_UNDERLAY_IFACE="${OPENPE_UNDERLAY_IFACE:-}"
export OPENPE_UNDERLAY_IFACE2="${OPENPE_UNDERLAY_IFACE2:-}"
mkdir -p "${STATE_DIR}"
mapfile -t APPLY_LINES < <(python3 - <<PY
import json, os
with open("${NODELINK}") as f:
    cfg = json.load(f)
env1 = os.environ.get("OPENPE_UNDERLAY_IFACE", "").strip()
env2 = os.environ.get("OPENPE_UNDERLAY_IFACE2", "").strip()
entries = []
for name, nc in cfg.get("nodes", {}).items():
    ip1 = nc.get("ipForKindLeaf", "")
    if ip1:
        iface1 = env1 or nc.get("ifaceForKindLeaf") or "toswitch1"
        entries.append({"node": name, "iface": iface1, "ip": ip1, "prefix": 24})
        print(f"{name}|{iface1}|{ip1}|24")
    # Dual-leaf opt-in: only when OPENPE_UNDERLAY_IFACE2 is set (matches DualLeafEnabled).
    if env2:
        ip2 = nc.get("ipForKindLeaf2", "")
        if ip2:
            iface2 = env2 or nc.get("ifaceForKindLeaf2") or "toswitch2"
            entries.append({"node": name, "iface": iface2, "ip": ip2, "prefix": 24})
            print(f"{name}|{iface2}|{ip2}|24")
def is_vlan_iface(name: str) -> bool:
    # parent.VID — VID is numeric (ens5f1.173). Avoid matching e.g. br-ex.
    if "." not in name:
        return False
    parent, _, vid = name.rpartition(".")
    return bool(parent) and vid.isdigit()

for e in entries:
    e["deleteLink"] = is_vlan_iface(e["iface"])

state = {
    "underlayIface": env1,
    "underlayIface2": env2,
    "entries": entries,
}
with open("${STATE_FILE}", "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY
)

if [[ ${#APPLY_LINES[@]} -eq 0 ]]; then
  echo "ERROR: no underlay addresses derived from nodelink.json" >&2
  rm -f "${STATE_FILE}"
  exit 1
fi
echo "Recorded planned ${STATE_FILE} (${#APPLY_LINES[@]} entries)"

LABELED_NODES=()
for line in "${APPLY_LINES[@]}"; do
  IFS='|' read -r node iface ip plen <<<"${line}"
  echo "  ${node}: ${iface}=${ip}/${plen}"
  node_exec "${node}" bash -c "
    set -e
    iface='${iface}'
    ip='${ip}'
    plen='${plen}'
    # Tagged underlay: parent.VID → create vlan subiface; flush parent IPv4 leftovers.
    case \"\${iface}\" in
      *.[0-9]*)
        parent=\"\${iface%.*}\"
        vid=\"\${iface##*.}\"
        if ! ip link show \"\${parent}\" >/dev/null 2>&1; then
          echo \"ERROR: parent iface \${parent} missing on ${node} (for \${iface})\" >&2
          ip -br link >&2 || true
          exit 1
        fi
        nmcli device set \"\${parent}\" managed no 2>/dev/null || true
        ip link set \"\${parent}\" up
        # Leftover underlay on bare parent steals routes from the vlan subiface.
        ip -4 addr flush dev \"\${parent}\" 2>/dev/null || true
        if ! ip link show \"\${iface}\" >/dev/null 2>&1; then
          echo \"  creating vlan \${iface} on \${parent} id \${vid}\"
          ip link add link \"\${parent}\" name \"\${iface}\" type vlan id \"\${vid}\"
        fi
        ;;
    esac
    if ! ip link show \"\${iface}\" >/dev/null 2>&1; then
      echo \"ERROR: iface \${iface} missing on ${node}\" >&2
      ip -br link >&2 || true
      exit 1
    fi
    nmcli device set \"\${iface}\" managed no 2>/dev/null || true
    ip link set \"\${iface}\" up
    # replace any existing IPv4 on this iface (test-owned underlay)
    ip -4 addr flush dev \"\${iface}\" 2>/dev/null || true
    ip -4 addr add \"\${ip}/\${plen}\" dev \"\${iface}\"
    ip -br addr show \"\${iface}\"
  "
  # Mark underlay-capable workers for e2e (sessions / frr_restart scheduling).
  if [[ ! " ${LABELED_NODES[*]} " =~ " ${node} " ]]; then
    oc label node "${node}" e2e.openperouter.io/underlay=true --overwrite
    LABELED_NODES+=("${node}")
  fi
done

echo "=== configure-bastion-worker-net complete ==="
