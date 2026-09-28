# OpenShift image build

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

## Refreshing RPM lockfiles

The `rpms.in.yaml` / `rpms.lock.yaml` pairs declare the RPM dependencies Konflux
prefetches for the hermetic OpenShift image builds. There are two scopes:

- **`openshift/`** — the build toolchain consumed by the `grout-builder` stage in
  `Dockerfile.edge.openshift` (the edge/grout image).
- **`openshift/frr/`** — the FRR runtime consumed by `Dockerfile.openshift` (the
  non-edge image). `frr` is pulled from Fast Datapath (FDP), via the
  `fast-datapath-for-rhel-10-x86_64-rpms` repository, instead of a prebuilt FRR
  base image.

Both scopes share `openshift/redhat.repo`.

## When to refresh

Update the relevant scope whenever:

- A package is added or removed in the `dnf install` lines of the corresponding
  Dockerfile (`grout-builder` stage for `openshift/`, the final stage for
  `openshift/frr/`).
- You want to pick up newer package versions of `registry.redhat.io/ubi10/ubi`.

### Steps

1. **Edit the scope's `rpms.in.yaml`** — add or remove entries in the `packages`
   list to match the packages installed by `dnf` in the corresponding Dockerfile
   stage.

2. **Regenerate the scope's `rpms.lock.yaml`**:
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

dnf config-manager --set-enabled "codeready-builder-for-rhel-10-x86_64-rpms,rhel-10-for-x86_64-baseos-rpms,rhel-10-for-x86_64-appstream-rpms,fast-datapath-for-rhel-10-x86_64-rpms";

# clean redhat.repo by removing all the disabled repositories
awk 'BEGIN{RS=""; ORS="\n\n"} /^#/ || /enabled = 1/' /etc/yum.repos.d/redhat.repo > /src/openshift/redhat.repo

cp /run/secrets/etc-pki-entitlement/* /etc/pki/entitlement/
skopeo login registry.redhat.io

# edge/grout toolchain scope
cd /src; rpm-lockfile-prototype --debug --bare --outfile openshift/rpms.lock.yaml openshift/rpms.in.yaml

# FDP FRR scope (non-edge image)
cd /src; rpm-lockfile-prototype --debug --bare --outfile openshift/frr/rpms.lock.yaml openshift/frr/rpms.in.yaml
```

3. **Commit the scope's `rpms.in.yaml` and `rpms.lock.yaml`** together.
