#!/usr/bin/env bash
# Remove underlay IPs applied by configure-bastion-worker-net.sh.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.e2e-bastion-state"
STATE_FILE="${STATE_DIR}/worker-net.json"

OPENPE_NS="${OPENPE_E2E_NAMESPACE:-openshift-openperouter}"
TEARDOWN="${OPENPE_E2E_TEARDOWN_WORKER_NET:-true}"

echo "=== teardown-bastion-worker-net ==="
echo "  OPENPE_E2E_TEARDOWN_WORKER_NET=${TEARDOWN}"

if [[ "${TEARDOWN}" == "false" ]]; then
  echo "Skipping worker underlay IP teardown"
  exit 0
fi

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "No state at ${STATE_FILE}; nothing to remove"
  exit 0
fi

if ! oc get ns "${OPENPE_NS}" >/dev/null 2>&1; then
  echo "WARNING: ${OPENPE_NS} missing; cannot nsenter to flush worker IPs" >&2
  rm -f "${STATE_FILE}"
  exit 0
fi

node_exec() {
  local node=$1; shift
  local pod
  pod=$(oc get pods -n "${OPENPE_NS}" -l app=controller \
    --field-selector "spec.nodeName=${node}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "${pod}" ]]; then
    echo "WARNING: no controller on ${node}; skip" >&2
    return 0
  fi
  oc exec -n "${OPENPE_NS}" "${pod}" -- nsenter -t 1 -m -u -i -n "$@" || true
}

mapfile -t FLUSH_LINES < <(python3 - <<PY
import json
with open("${STATE_FILE}") as f:
    cfg = json.load(f)
for e in cfg.get("entries", []):
    print(f"{e['node']}|{e['iface']}|{e['ip']}|{e.get('prefix', 24)}")
PY
)

for line in "${FLUSH_LINES[@]}"; do
  IFS='|' read -r node iface ip plen <<<"${line}"
  echo "  flush ${node}: ${iface} (${ip}/${plen})"
  node_exec "${node}" bash -c "
    ip -4 addr del '${ip}/${plen}' dev '${iface}' 2>/dev/null || true
    ip -br addr show '${iface}' 2>/dev/null || true
  "
done

rm -f "${STATE_FILE}"
echo "=== teardown-bastion-worker-net complete ==="
