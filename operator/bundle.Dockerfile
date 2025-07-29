FROM scratch

# Core bundle labels.
LABEL operators.operatorframework.io.bundle.mediatype.v1=registry+v1
LABEL operators.operatorframework.io.bundle.manifests.v1=manifests/
LABEL operators.operatorframework.io.bundle.metadata.v1=metadata/
LABEL operators.operatorframework.io.bundle.package.v1=openperouter-operator
LABEL operators.operatorframework.io.bundle.channels.v1=alpha
LABEL operators.operatorframework.io.metrics.builder=operator-sdk-v1.39.2
LABEL operators.operatorframework.io.metrics.mediatype.v1=metrics+v1
LABEL operators.operatorframework.io.metrics.project_layout=go.kubebuilder.io/v4
LABEL com.redhat.component="openperouter-operator" \
    name="openperouter-operator" \
    version="${CI_CONTAINER_VERSION}" \
    summary="openperouter-operator" \
    io.openshift.expose-services="" \
    io.openshift.tags="openperouter-operator" \
    io.k8s.display-name="openperouter-operator" \
    io.k8s.description="openperouter-operator" \
    description="openperouter-operator" \
    distribution-scope="public" \
    release="4.20" \
    url="https://github.com/openperouter/openperouter" \
    vendor="Red Hat, Inc."
# Copy files to locations specified by labels.
COPY bundle/stable /manifests/
COPY bundle/metadata /metadata/
