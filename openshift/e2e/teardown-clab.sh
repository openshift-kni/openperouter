#!/usr/bin/env bash
# Tear down the OpenPE ocp.clab fabric on this host.
#
# Safe for bastion: does NOT remove toswitch* bridges or touch eth0/mgmt.
# Works around containerlab+podman destroy SEGV by falling back to podman rm.
#
# Usage:
#   export OPENPE_E2E_PROVIDER=bastion CLAB_RUNTIME=podman   # optional; defaults apply
#   ./openshift/e2e/teardown-clab.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPO="${SCRIPT_DIR}/ocp.clab.yml"
PROVIDER="${OPENPE_E2E_PROVIDER:-dev-scripts}"
MGMT_IFACE="${CLAB_BASTION_MGMT_IFACE:-eth0}"

if [[ "${PROVIDER}" == "bastion" ]]; then
  RUNTIME="${CLAB_RUNTIME:-${OPENPE_CLAB_RUNTIME:-podman}}"
else
  RUNTIME="${CLAB_RUNTIME:-${OPENPE_CLAB_RUNTIME:-docker}}"
fi

if command -v clab >/dev/null 2>&1; then
  CLAB_BIN=clab
elif command -v containerlab >/dev/null 2>&1; then
  CLAB_BIN=containerlab
else
  echo "ERROR: clab/containerlab not found" >&2
  exit 1
fi

assert_mgmt_default() {
  if [[ "${PROVIDER}" != "bastion" ]]; then
    return 0
  fi
  local def
  def="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
  if [[ -z "${def}" ]]; then
    echo "ERROR: no default route after teardown (expected via ${MGMT_IFACE})" >&2
    return 1
  fi
  if [[ "${def}" != "${MGMT_IFACE}" ]]; then
    echo "ERROR: default route on ${def}, expected ${MGMT_IFACE} (SSH/mgmt broken risk)" >&2
    return 1
  fi
  echo "OK: default route still on ${MGMT_IFACE}"
}

echo "=== teardown-clab ==="
echo "  provider=${PROVIDER} runtime=${RUNTIME} topo=${TOPO}"

if [[ "${PROVIDER}" == "bastion" ]]; then
  assert_mgmt_default || true
fi

# Prefer explicit destroy; ignore non-zero / SEGV (podman path is known flaky).
set +e
sudo "${CLAB_BIN}" destroy --runtime "${RUNTIME}" --topo "${TOPO}" --cleanup
destroy_rc=$?
set -e
if [[ "${destroy_rc}" -ne 0 ]]; then
  echo "WARN: clab destroy exited ${destroy_rc} (often SEGV with podman); removing leftovers"
fi

if [[ "${RUNTIME}" == "podman" ]]; then
  sudo podman ps -a --filter name=clab-kind --format '{{.Names}}' \
    | xargs -r sudo podman rm -f 2>/dev/null || true
elif [[ "${RUNTIME}" == "docker" ]]; then
  sudo docker ps -a --filter name=clab-kind --format '{{.Names}}' \
    | xargs -r sudo docker rm -f 2>/dev/null || true
fi

assert_mgmt_default
echo "=== teardown-clab complete ==="
