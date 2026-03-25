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

   > Packages from external repos (e.g. `frr`, `frr-headers` from the
   > `mruprich/FRR10` copr) cannot be tracked here — only packages available
   > in the CentOS Stream 10 repos listed under `contentOrigin`.

2. **Regenerate `rpms.lock.yaml`**:

   ```bash
   rpm-lockfile-prototype \
     --image registry.redhat.io/ubi10/ubi \
     --outfile openshift/rpms.lock.yaml \
     openshift/rpms.in.yaml
   ```

3. **Commit both files** together.
