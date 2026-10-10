#!/usr/bin/env bash
# Rootful podman wrapper for bastion e2e.
# setup-clab.sh deploys with "sudo podman"; Ginkgo uses CONTAINER_RUNTIME as a
# single binary, so point CONTAINER_RUNTIME at this script.
exec sudo /usr/bin/podman "$@"
