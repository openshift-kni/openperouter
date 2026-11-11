# OpenShift image build

First, register the subscription
```
$ subscription-manager register --username ... --password ...

# or

$ subscription-manager register --org ... --activationkey ...
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
               -f Dockerfile.openshift .
```
