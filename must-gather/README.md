# OpenPERouter must-gather

The OpenPERouter must-gather image collects OpenPERouter related objects and
logs from an OpenShift cluster, making them available for post-mortems and
debugging.

It is a thin must-gather compatible wrapper around the repository
[`tools/inspect`](../tools/inspect/README.md) toolkit, which is embedded in the
image. The toolkit collects the OpenPERouter namespace objects, workload logs,
CRDs (`underlays`, `l2vnis`, `l3vnis`, `l3passthroughs`, `rawfrrconfigs`,
`routernodeconfigurationstatuses`) and per-node routing/network infrastructure
information (FRR/`vtysh` output, `perouter` netns state, BGP/EVPN/BFD info).

## Usage

Run the standard must-gather tooling, passing the OpenPERouter must-gather image
with the `--image` option:

```bash
$ oc adm must-gather --image=quay.io/redhat-user-workloads/telco-5g-tenant/openperouter-operator-edge-5-1:must-gather-latest
```

By default the plugin collects from the `openperouter-system` namespace. The
namespace and log window can be overridden with environment variables passed
through must-gather:

```bash
$ oc adm must-gather \
    --image=quay.io/redhat-user-workloads/telco-5g-tenant/openperouter-operator-edge-5-1:must-gather-latest \
    -- NS=my-namespace SINCE_DURATION=10m /usr/bin/gather
```

## Output

Artifacts follow the layout produced by the inspect toolkit. See
[`tools/inspect/README.md`](../tools/inspect/README.md) for the full output
description. In short:

- `timestamp` - collection timestamp
- `inspect.log` - collection log
- `node_info/` - per-node network and routing infrastructure information
- `<openperouter namespace>/` - namespace objects and workload logs
- `<namespace>/` - per-namespace OpenPERouter config resources

## Host mode

When OpenPERouter runs in host (systemd) mode, the router container is not
managed by the cluster, so its info cannot be collected through the cluster API.
The image also ships the `inspect_host` script (at
`/usr/share/openperouter/inspect/inspect_host`) for this case: it can be copied
out of the image and run directly on the target node. See
[`tools/inspect/README.md`](../tools/inspect/README.md#inspect-openperouter-nodes-when-running-on-systemd-mode)
for details. Streamlining host-mode collection through must-gather is planned as
a follow-up.

## Build and publish

The image is built and published by Konflux/Tekton (see the
`.tekton/openperouter-operator-edge-must-gather-*.yaml` pipeline files and
`Dockerfile.must-gather.openshift`).

These pipelines reuse the existing `openperouter-operator-edge-5-1` Konflux
Component's build-pipeline service account, publishing the image under that
component's image repository with a distinct `must-gather-` tag prefix
(`must-gather-{{revision}}`, `must-gather-latest`, `must-gather-pr-<number>`)
instead of registering a brand new Component. This follows the same pattern
already used by `openperouter-operator-dev-push.yaml`, which reuses the
bundle component's service account. The `must-gather-` prefix keeps this
pipeline's tags from ever colliding with the real edge image's own `latest`
and `pr-<number>` tags on that repository.

For local builds (useful for debugging the must-gather logic) you can reuse the
generic `docker-build` make target, pointing it at the must-gather Dockerfile:

```bash
$ make docker-build DOCKERFILE=Dockerfile.must-gather.openshift IMG_NAME=must-gather
```

Using a custom registry and tag:

```bash
$ make docker-build DOCKERFILE=Dockerfile.must-gather.openshift IMG_NAME=must-gather \
    IMG_REPO=example.com/openperouter IMG_TAG=latest
```
