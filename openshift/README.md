# OpenShift Downstream Images

Production and staging container images for the OpenPERouter operator on OpenShift.

## Image streams:

### Production

#### [`registry.redhat.io/openshift4-dev-preview-beta/openperouter-rhel9-operator`](https://catalog.redhat.com/en/software/containers/openshift4-dev-preview-beta/openperouter-rhel9-operator/685d58c568b1e69d3c4ba222)

Operator image. Contains PERouter binaries and latest RH approved FRR RPMs.
Source: `Dockerfile.openshift`

#### [`registry.redhat.io/openshift4-dev-preview-beta/openperouter-operator-bundle`](https://catalog.redhat.com/en/software/containers/openshift4-dev-preview-beta/openperouter-operator-bundle/685d58c58e4198555c77cfaf)

Production operator bundle. Can be installed via [Catalog Subscription](#catalog-subscription) or
via [Bundle Deployment](#bundle-deployment).
Source: `operator/bundle.Dockerfile.openshift`

#### [`registry.redhat.io/openshift4-dev-preview-beta/openperouter-edge-rhel10-operator`](https://catalog.redhat.com/en/software/containers/openshift4-dev-preview-beta/openperouter-edge-rhel10-operator/69ef0b468eb7117ec2f9dbb8)

Operartor edge image with:
- PERouter code
- FRR, Grout, DPDK binaries built from sources (see git submodules and `Dockerfile.edge.openshift`)

### Quay

Before being available in production registries, images can be pulled for testing from https://quay.io.

#### [`quay.io/redhat-user-workloads/telco-5g-tenant/openperouter-operator-4-22`](https://quay.io/repository/redhat-user-workloads/telco-5g-tenant/openperouter-operator-4-22?)

Operator image
tags:
- `latest`: last build from the release branch
- `pr-<N>`: built with last pushed commit for PR N
- `on-pr-<revision>`: built from the specific PR revision
- `<revision>`: built from the specifig git revision


#### [`quay.io/redhat-user-workloads/telco-5g-tenant/openperouter-operator-bundle-4-22`](https://quay.io/repository/redhat-user-workloads/telco-5g-tenant/openperouter-operator-bundle-4-22)

Operator bundle image
tags:
- `latest`: **be aware**: the operator image referenced in this build is **not** the latest from quay.io published image, but the one referenced 
  in `operator/bundle/overlay/pin_images.in.yaml` at the time of the bundle build.
- `pr-<N>`: reference the last operator image build from PR N. Can be installed via [Bundle Deployment](#bundle-deployment).
- `on-pr-<revision>`: **do not use**


#### [`quay.io/redhat-user-workloads/telco-5g-tenant/openperouter-operator-4-22`](https://quay.io/repository/redhat-user-workloads/telco-5g-tenant/openperouter-operator-4-22?)

Operator edge image
tags:
- `latest`: last build from the release branch
- `pr-<N>`: built with last pushed commit for PR N
- `on-pr-<revision>`: built from the specific PR revision
- `<revision>`: built from the specifig git revision

## Install operator downstream builds

### Catalog Subscription

Create the following resource to install
```
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-openperouter
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-openperouter
  namespace: openshift-openperouter
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openperouter-operator
  namespace: openshift-openperouter
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: openperouter-operator
  source: openperouter-catalog
  sourceNamespace: openshift-marketplace
EOF
```

### Bundle Deployment

A bundle image can be deployed via:

```sh
BUNDLE_IMAGE=registry.redhat.io/openshift4-dev-preview-beta/openperouter-operator-bundle:v4.21

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-openperouter
EOF

operator-sdk run bundle "$BUNDLE_IMAGE" \
  --namespace openshift-openperouter \
  --timeout 5m
```


## OpenShift edge image

### Build

First, register the subscription
```
$ subscription-manager register --force --username ... --password ...

# or

$ subscription-manager register --force --org ... --activationkey ...
```

Then, build the image with
```
# Share the entitlement with the build
TMPDIR=$(mktemp -d)
cp -r /etc/pki/entitlement "$TMPDIR/entitlement"
cp -r /etc/rhsm "$TMPDIR/rhsm"

# Build the image
podman build -v "$TMPDIR/entitlement:/run/secrets/etc-pki-entitlement:Z"  \
               -v "$TMPDIR/rhsm:/run/secrets/rhsm:Z" \
               --build-arg BASE_IMAGE=registry.redhat.io/ubi10/ubi:10.1-1774545609 \
               -f Dockerfile.edge.openshift .
```

### Refreshing RPM lockfiles

The `rpms.in.yaml` and `rpms.lock.yaml` files declare the RPM dependencies
needed by the `grout-builder` stage in `Dockerfile.openshift`. Konflux uses
them to prefetch packages for hermetic builds.

### When to refresh

Update these files whenever:

- A package is added or removed in `Dockerfile.edge.openshift` (the `dnf install`
  lines in the `grout-builder` stage).
- You want to pick up newer package versions of `registry.redhat.io/ubi10/ubi`.

### Steps

1. **Edit `rpms.in.yaml`** — add or remove entries in the `packages` list to
   match the packages installed by `dnf` in the `grout-builder` stage.

2. **Regenerate `rpms.lock.yaml`**:
 Follow instructions at 
 https://konflux-ci.dev/docs/building/activation-keys-subscription/#configuring-an-rpm-lockfile-for-hermetic-builds

 
```bash
# Share the entitlement with podman
TMPDIR=$(mktemp -d)
cp -r /etc/pki/entitlement "$TMPDIR/entitlement"
cp -r /etc/rhsm "$TMPDIR/rhsm"

podman run -it -v `pwd`:/src:Z -v "$TMPDIR/entitlement:/run/secrets/etc-pki-entitlement:Z"  \
               -v "$TMPDIR/rhsm:/run/secrets/rhsm:Z" registry.redhat.io/ubi10/ubi:10.1-1774545609 bash

dnf install -y pip skopeo
pip install https://github.com/konflux-ci/rpm-lockfile-prototype/archive/refs/tags/v0.13.1.tar.gz

dnf config-manager --set-enabled "codeready-builder-for-rhel-10-x86_64-rpms,rhel-10-for-x86_64-baseos-rpms,rhel-10-for-x86_64-appstream-rpms";

# clean redhat.repo by removing all the disabled repositories
awk 'BEGIN{RS=""; ORS="\n\n"} /^#/ || /enabled = 1/' /etc/yum.repos.d/redhat.repo > /src/openshift/redhat.repo

cp /run/secrets/etc-pki-entitlement/* /etc/pki/entitlement/
skopeo login registry.redhat.io

cd /src; rpm-lockfile-prototype --debug --bare --outfile openshift/rpms.lock.yaml openshift/rpms.in.yaml
```

3. **Commit both files** together.
