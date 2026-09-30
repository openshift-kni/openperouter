# OpenShift / cluster e2e environments

This directory wires the OpenPE **containerlab fabric** to a real OpenShift
cluster (not KIND). Upstream KIND e2e remains under `clab/` + `e2etests/` and
must keep working.

## Compatibility contract (do not break)

Any bastion / lab changes on this branch must preserve:

| Provider | How it runs today | Entry points |
| --- | --- | --- |
| **KIND** | Full in-clab KIND (`pe-kind*`) | Repo `make deploy` / `clab/singlecluster/kind.clab.yml` + `e2etests` |
| **Virtual OCP** | OCP VMs via **dev-scripts** + libvirt nets `toswitch1`/`toswitch2` | `openshift/e2e/deploy.sh` → `setup-clab.sh` (default) |
| **Bastion lab** (new) | Clab on a bastion; cluster workers reached over lab NIC (`eth1`/`eth2`) / VLAN bridges | `make e2e-bastion` / `OPENPE_E2E_PROVIDER=bastion` |

Rules:

1. **Default** `OPENPE_E2E_PROVIDER` is `dev-scripts` — same behavior as before this branch.
2. Do **not** remove or rename `toswitch1` / `toswitch2` in `ocp.clab.yml` without updating virtual-OCP scripts.
3. Prefer env flags / thin wrappers over forking the topology YAML.
4. Bastion mode must not set a default gateway on the lab NIC (breaks SSH / mgmt). See bastion notes below.

## Virtual OCP (dev-scripts) — default

```bash
export KUBECONFIG=/root/dev-scripts/ocp/ostest/auth/kubeconfig
./openshift/e2e/deploy.sh
# or only fabric:
./openshift/e2e/setup-clab.sh
```

Prerequisites: `EXTRA_NETWORK_NAMES` / post-install `toswitch1` `toswitch2`, Docker, OpenPE + frr-k8s on cluster.

## Bastion lab (opt-in)

Target: QE bastions (e.g. `bastion-hlxcl7`) with:

- `eth0` = mgmt / SSH / **default route only**
- `eth1` = lab VLAN → `toswitch1` (no gateway; `ipv4.never-default yes`)
- `eth2` = lab VLAN → `toswitch2` (same rules)
- Clab fabric on the bastion; same `ocp.clab.yml` bridges named `toswitch1`/`toswitch2`

### CI / full lifecycle (setup → test → teardown)

This is the bastion/OCP counterpart to KIND `make deploy` + e2e + clean.  
**Do not** use KIND `make deploy` on the bastion. Operators (OpenPE + frr-k8s) are installed by CI before this job.

```bash
export KUBECONFIG=/path/to/ocp/kubeconfig
set -a && source openshift/e2e/bastion.env.example && set +a

# Preferred:
make e2e-bastion
# same as: ./openshift/e2e/e2e-bastion.sh
```

`make` exports KIND’s `bin/kubeconfig` as `KUBECONFIG`. For bastion CI use:

```bash
export OPENPE_KUBECONFIG=/path/to/ocp/kubeconfig
make e2e-bastion
# or bypass make: KUBECONFIG=/path/to/ocp/kubeconfig ./openshift/e2e/e2e-bastion.sh
```

Flow:

1. `deploy-bastion.sh` → bridges + `setup-clab.sh` (fabric)
2. `run_tests.sh` → existing focused Ginkgo suite (`Single.Session.Baseline`, …)
3. `teardown-clab.sh` → always (EXIT trap); keeps `toswitch*` / mgmt NICs; asserts default route stays on `eth0`

Debug (keep fabric): `OPENPE_E2E_SKIP_TEARDOWN=true make e2e-bastion`

### Shared `CLAB_*` variables (OpenPE + MetalLB)

Same bastion will later host MetalLB **external FRR** containers. Use one var set:

| Variable | Purpose | Example (hlxcl7) |
| --- | --- | --- |
| `CLAB_EXECUTOR` | `local` (CI/bastion) or `ssh` (laptop later) | `local` |
| `CLAB_BASTION_HOST` | Bastion hostname/IP | `registry.hlxcl7.lab.eng.tlv2.redhat.com` |
| `CLAB_BASTION_USER` | SSH user | `telcov10n` |
| `CLAB_BASTION_SSH` | `user@host` for ssh | `telcov10n@registry.hlxcl7…` |
| `CLAB_BASTION_WORKDIR` | Checkout / topo dir on bastion | `/home/telcov10n/openperouter` |
| `CLAB_RUNTIME` | `podman` or `docker` | `podman` |
| `CLAB_BASTION_LAB_IFACE` | Lab NIC (never default route) | `eth1` |
| `CLAB_BASTION_ATTACH_LAB_IFACE` | Enslave lab NIC to `toswitch1` | `true` |
| `OPENPE_E2E_PROVIDER` | OpenPE only: `dev-scripts` \| `bastion` | `bastion` |
| `KUBECONFIG` | Cluster under test | path to hlxcl7 kubeconfig |

See `bastion.env.example`. Phase 1: **`CLAB_EXECUTOR=local` only** (run tests + clab on the bastion). `ssh` executor comes later for laptop-driven runs; CI stays `local`.

```bash
set -a && source openshift/e2e/bastion.env.example && set +a
export KUBECONFIG=/path/to/ocp/kubeconfig

# Bring-up only (no tests / no teardown):
./openshift/e2e/deploy-bastion.sh

# Or step by step:
# ./openshift/e2e/setup-bastion-bridges.sh
# ./openshift/e2e/setup-clab.sh
# ./openshift/e2e/run_tests.sh
# ./openshift/e2e/teardown-clab.sh
```

`setup-clab.sh` with `OPENPE_E2E_PROVIDER=bastion`:

- Uses `CLAB_RUNTIME` (default **podman**)
- Skips libvirt/virsh DHCP and `ostest_*` NIC rename
- Writes planned `nodelink.json` (`OPENPE_BASTION_SKIP_WORKER_NET=true` by default)
- Refuses to continue if default route is on `eth1`/`eth2`

**Still TODO for bastion:** apply worker secondary NIC IPs on the real cluster (no virsh) after the lab uplink is cabled — required for Baseline e2e to pass end-to-end.

## KIND

Unaffected by this directory. Use the existing Kind-based developer and CI flows.

## Files

| File | Role |
| --- | --- |
| `ocp.clab.yml` | Fabric topo; bridges `toswitch1`/`toswitch2` (shared by virtual OCP + bastion) |
| `setup-clab.sh` | Deploy fabric, IPs, setups, nodelink (provider-aware) |
| `teardown-clab.sh` | Destroy fabric only (podman-safe); keep bridges/mgmt; assert eth0 default |
| `setup_extra_networks.sh` | **Virtual OCP only** — libvirt extra nets |
| `setup-bastion-bridges.sh` | **Bastion only** — create `toswitch*` + NM-harden lab NICs (no SSH theft) |
| `deploy-bastion.sh` | **Bastion only** — bridges + `setup-clab.sh` (not KIND `make deploy`) |
| `e2e-bastion.sh` | **Bastion only** — deploy → `run_tests.sh` → teardown (`make e2e-bastion`) |
| `ip_map_ocp.txt` | Static IPs inside clab nodes |
| `deploy.sh` | Full virtual-OCP bring-up |
| `run_tests.sh` | Focused e2e against `nodelink.json` |
