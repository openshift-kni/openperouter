# Build the manager binary
FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:rhel_9_golang_1.24 AS builder

ARG GIT_COMMIT=dev
ARG GIT_BRANCH=dev
ARG TARGETOS
ARG TARGETARCH

WORKDIR $GOPATH/openperouter

COPY . .

RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -v -mod=vendor -o reloader ./cmd/reloader \
  && \
  CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -v -mod=vendor -o controller ./cmd/hostcontroller \
  && \
  CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -v -mod=vendor -o cp-tool ./cmd/cp-tool \
  && \
  CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -v -mod=vendor -o nodemarker ./cmd/nodemarker \
  && \
  CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -v -mod=vendor -o operatorbinary ./operator

FROM registry.access.redhat.com/ubi9-minimal:9.4
WORKDIR /
COPY --from=builder /go/openperouter/reloader .
COPY --from=builder /go/openperouter/controller .
COPY --from=builder /go/openperouter/cp-tool .
COPY --from=builder /go/openperouter/nodemarker .
COPY --from=builder /go/openperouter/operatorbinary ./operator
COPY operator/bindata bindata

LABEL com.redhat.component="openperouter" \
    name="openperouter" \
    version="${CI_CONTAINER_VERSION}" \
    summary="openperouter" \
    io.openshift.expose-services="" \
    io.openshift.tags="openperouter" \
    io.k8s.display-name="openperouter" \
    io.k8s.description="openperouter" \
    description="openperouter" \
    distribution-scope="public" \
    release="4.20" \
    url="https://github.com/openperouter/openperouter" \
    vendor="Red Hat, Inc."

ENTRYPOINT ["/controller"]
