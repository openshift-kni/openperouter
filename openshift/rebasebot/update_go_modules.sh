#!/bin/bash

# Rebasebot post-rebase hook that tidies and vendors only the root go module.
# The builtin --update-go-modules hook walks every go.mod in the repository,
# but only the root module is vendored downstream: e2etests, website and
# hack/benchmarkcheck must be left untouched.
#
# See https://github.com/openshift-eng/rebasebot#golang-vendor-update

set -euo pipefail

if [[ -z "${REBASEBOT_SOURCE:-}" ]]; then
    echo "The environment variable REBASEBOT_SOURCE is not set." >&2
    exit 1
fi

cd "${REBASEBOT_WORKING_DIR:-.}"

# Start from the upstream go.mod and go.sum so that conflicts resolved during
# the rebase do not leak into the module definition.
git checkout "refs/remotes/source/${REBASEBOT_SOURCE}" -- go.mod go.sum

echo "Running go mod tidy"
go mod tidy

echo "Running go mod vendor"
go mod vendor

if [[ -z $(git status --porcelain -- go.mod go.sum vendor) ]]; then
    echo "Go modules are up to date"
    exit 0
fi

author_flag=()
if [[ -n "${REBASEBOT_GIT_USERNAME:-}" && -n "${REBASEBOT_GIT_EMAIL:-}" ]]; then
    author_flag=(--author="${REBASEBOT_GIT_USERNAME} <${REBASEBOT_GIT_EMAIL}>")
fi

git add -A -- go.mod go.sum vendor
git commit "${author_flag[@]}" -q -m "ds: run `go mod tidy` and `go mod vendor`"
