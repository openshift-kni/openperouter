#!/bin/bash
set -o errexit
set -x

CONTAINER_ENGINE=${CONTAINER_ENGINE:-docker}

GOLANGCI_LINT_VERSION="${GOLANGCI_LINT_VERSION:-2.9.0}"
TIMEOUT="10m0s"
ENV="${ENV:-container}"

function _run() {
	if [ "$ENV" == "container" ]; then
	     $CONTAINER_ENGINE run --rm \
			-v "$(git rev-parse --show-toplevel)":/app \
			-w /app \
			docker.io/golangci/golangci-lint:v"$GOLANGCI_LINT_VERSION" \
			"$@"
	else
		curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin v"$GOLANGCI_LINT_VERSION"
		$@
	fi
}

function build() {
	_run golangci-lint custom
}

function run() {
	_run bin/golangci-lint-custom run --timeout $TIMEOUT ./...
}

$@
