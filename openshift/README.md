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
  rpm-lockfile-prototype --debug --bare --outfile openshift/rpms.lock.yaml openshift/rpms.in.yaml > openshift/debug.log
   ```

3. **Commit both files** together.
