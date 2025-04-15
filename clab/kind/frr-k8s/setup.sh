#!/bin/bash

kubectl apply -f https://raw.githubusercontent.com/metallb/frr-k8s/refs/tags/v0.0.17/config/all-in-one/frr-k8s.yaml
sleep 2s
kubectl -n frr-k8s-system wait --for=condition=Ready --all pods --timeout 300s

