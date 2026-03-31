# OpenShift image build

First, register the subscription
```
$ subscription-manager register --username ... --password ...

# or

$ subscription-manager register --org ... --activationkey ...
```

Then, build the image with
```
$ TMPDIR=$(mktemp -d)
  cp -r /etc/pki/entitlement "$TMPDIR/entitlement"
  cp -r /etc/rhsm "$TMPDIR/rhsm"
  

$ podman build -v "$TMPDIR/entitlement:/run/secrets/etc-pki-entitlement:Z"  \
               -v "$TMPDIR/rhsm:/run/secrets/rhsm:Z" \
               -f Dockerfile.openshift .

$ rm -rf "$TMPDIR"  
```

## Refreshing RPM lockfiles

The `rpms.in.yaml` and `rpms.lock.yaml` files declare the RPM dependencies
needed by the `grout-builder` stage in `Dockerfile.openshift`. Konflux uses
them to prefetch packages for hermetic builds.

## When to refresh

Update these files whenever:

- A package is added or removed in `Dockerfile.openshift` (the `dnf install`
  lines in the `grout-builder` stage).
- You want to pick up newer package versions from CentOS Stream 10.

### Steps

1. **Edit `rpms.in.yaml`** — add or remove entries in the `packages` list to
   match the packages installed by `dnf` in the `grout-builder` stage.

2. **Regenerate `rpms.lock.yaml`**:
 Follow instructions at 
 https://konflux-ci.dev/docs/building/activation-keys-subscription/#configuring-an-rpm-lockfile-for-hermetic-builds

 
```bash
$  podman run -it -v `pwd`:/src:Z -v "$TMPDIR/entitlement:/run/secrets/etc-pki-entitlement:Z"  \
               -v "$TMPDIR/rhsm:/run/secrets/rhsm:Z" registry.redhat.io/ubi10/ubi:10.1-1774545609 bash

$ dnf install -y pip skopeo
$ pip install https://github.com/konflux-ci/rpm-lockfile-prototype/archive/refs/tags/v0.13.1.tar.gz
$ cp /etc/yum.repos.d/redhat.repo /src/openshift/redhat.repo
<clean redhat.repo by removing all the disabled repositories>
$ cp /run/secrets/etc-pki-entitlement/* /etc/pki/entitlement/
$ skopeo login registry.redhat.io
$ cd /src; rpm-lockfile-prototype --debug --bare --outfile openshift/rpms.lock.yaml openshift/rpms.in.yaml


$ rpm-lockfile-prototype --debug --bare --outfile openshift/rpms.lock.yaml openshift/rpms.in.yaml > openshift/debug.log
```

3. **Commit both files** together.
