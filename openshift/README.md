# Refreshing RPM lockfiles

The `rpms.in.yaml` and `rpms.lock.yaml` files declare the RPM dependencies
needed by the `grout-builder` stage in `Dockerfile.openshift`. Konflux uses
them to prefetch packages for hermetic builds.

## When to refresh

Update these files whenever:

- A package is added or removed in `Dockerfile.openshift` (the `dnf install`
  lines in the `grout-builder` stage).
- You want to pick up newer package versions from CentOS Stream 10.

## Prerequisites

Install the lock file generator:

```bash
pip install rpm-lockfile-prototype
```

You also need `skopeo` installed and access to `registry.redhat.io` (run
`podman login registry.redhat.io` if not already authenticated).

## Steps

1. **Edit `rpms.in.yaml`** — add or remove entries in the `packages` list to
   match the packages installed by `dnf` in the `grout-builder` stage.

2. **Regenerate `rpms.lock.yaml`**:
 Follow instructions at 
 https://konflux-ci.dev/docs/building/activation-keys-subscription/#configuring-an-rpm-lockfile-for-hermetic-builds

 
```bash
$ docker run -v `pwd`:/src -it registry.redhat.io/rhel10/rhel-bootc:10.1  bash

$ subscription-manager register --username ... --password ...
$ <enable codeready-builder-for-rhel-10-x86_64-rpms repo in /etc/yum.repos.d/redhat.repo
$ dnf install -y pip skopeo
$ pip install https://github.com/konflux-ci/rpm-lockfile-prototype/archive/refs/tags/v0.13.1.tar.gz
$ cp /etc/yum.repos.d/redhat.repo /src/openshift/redhat.repo
<clean redhat.repo by removing all the disabled repositories>
$ skopeo login registry.redhat.io
$ cd /src; rpm-lockfile-prototype rpm-lockfile-prototype --debug --bare --outfile openshift/rpms.lock.yaml openshift/rpms.in.yaml



  rpm-lockfile-prototype --debug --bare --outfile openshift/rpms.lock.yaml openshift/rpms.in.yaml > openshift/debug.log
```

3. **Commit both files** together.
