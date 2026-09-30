#!/usr/bin/env bash
# Apply underlay IPs on selected worker nodes for bastion e2e.
# Uses nodelink.json (written by setup-clab.sh) + OPENPE_UNDERLAY_IFACE*.
# Records state for teardown-bastion-worker-net.sh.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODELINK="${SCRIPT_DIR}/nodelink.json"
STATE_DIR="${SCRIPT_DIR}/.e2e-bastion-state"
STATE_FILE="${STATE_DIR}/worker-net.json"

OPENPE_NS="${OPENPE_E2E_NAMESPACE:-openshift-openperouter}"
IFACE1="${OPENPE_UNDERLAY_IFACE:-toswitch1}"
IFACE2="${OPENPE_UNDERLAY_IFACE2:-}"

if [[ ! -f "${NODELINK}" ]]; then
  echo "ERROR: ${NODELINK} missing — run setup-clab.sh / deploy-bastion first" >&2
  exit 1
fi

if ! oc get ns "${OPENPE_NS}" >/dev/null 2>&1; then
  echo "ERROR: OpenPE namespace ${OPENPE_NS} not found" >&2
  exit 1
fi

echo "=== configure-bastion-worker-net ==="
echo "  namespace=${OPENPE_NS} iface1=${IFACE1} iface2=${IFACE2:-<unset>}"
echo "  nodelink=${NODELINK}"

node_exec() {
  local node=$1; shift
  local pod
  pod=$(oc get pods -n "${OPENPE_NS}" -l app=controller \
    --field-selector "spec.nodeName=${node}" \
    -o jsonpath='{.items[0].metadata.name}')
  if [[ -z "${pod}" ]]; then
    echo "ERROR: no controller pod on ${node} in ${OPENPE_NS}" >&2
    return 1
  fi
  oc exec -n "${OPENPE_NS}" "${pod}" -- nsenter -t 1 -m -u -i -n "$@"
}

# Build apply list from nodelink (python for portable JSON).
export OPENPE_UNDERLAY_IFACE="${IFACE1}"
export OPENPE_UNDERLAY_IFACE2="${IFACE2}"
mapfile -t APPLY_LINES < <(python3 - <<PY
import json, os
with open("${NODELINK}") as f:
    cfg = json.load(f)
iface1 = os.environ.get("OPENPE_UNDERLAY_IFACE", "toswitch1")
iface2 = os.environ.get("OPENPE_UNDERLAY_IFACE2", "")
for name, nc in cfg.get("nodes", {}).items():
    ip1 = nc.get("ipForKindLeaf", "")
    if ip1:
        print(f"{name}|{iface1}|{ip1}|24")
    if iface2:
        ip2 = nc.get("ipForKindLeaf2", "")
        if ip2:
            print(f"{name}|{iface2}|{ip2}|24")
PY
)

if [[ ${#APPLY_LINES[@]} -eq 0 ]]; then
  echo "ERROR: no underlay addresses derived from nodelink.json" >&2
  exit 1
fi

mkdir -p "${STATE_DIR}"
STATE_JSON='{"entries":['
FIRST=1

for line in "${APPLY_LINES[@]}"; do
  IFS='|' read -r node iface ip plen <<<"${line}"
  echo "  ${node}: ${iface}=${ip}/${plen}"
  node_exec "${node}" bash -c "
    set -e
    nmcli device set '${iface}' managed no 2>/dev/null || true
    ip link set '${iface}' up
    # replace any existing IPv4 on this iface (test-owned underlay)
    ip -4 addr flush dev '${iface}' 2>/dev/null || true
    ip -4 addr add '${ip}/${plen}' dev '${iface}'
    ip -br addr show '${iface}'
  "
  if [[ "${FIRST}" -eq 1 ]]; then
    FIRST=0
  else
    STATE_JSON+=','
  fi
  STATE_JSON+=$(printf '{"node":"%s","iface":"%s","ip":"%s","prefix":%s}' \
    "${node}" "${iface}" "${ip}" "${plen}")
done

STATE_JSON+=']}'
printf '%s\n' "${STATE_JSON}" > "${STATE_FILE}"
echo "Recorded ${STATE_FILE}"
echo "=== configure-bastion-worker-net complete ==="
