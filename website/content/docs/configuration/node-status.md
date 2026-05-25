---
weight: 65
title: "Node Status"
description: "How to check specific node's router configuration status"
icon: "article"
date: "2025-06-15T15:03:22+02:00"
lastmod: "2025-06-15T15:03:22+02:00"
toc: true
---

## Node Status

{{< hint warning >}}
**Work in progress**: 
{{< /hint >}}

The node router configuration status can be viewed and monitored via the RouterNodeConfigurationStatus CRD.

Each node will have an associated RouterNodeConfigurationStatus CR resource indicate this node router configuration status.
It reports the outcome of all configuration resources (e.g.: Underlay, L3VNI, L2VNI) affecting the node. 
In other words its the source of truth configuration health on that node.

Nodes:
```shell
$ kubectl get no
NAME                    STATUS   ROLES           AGE   VERSION
pe-kind-control-plane   Ready    control-plane   19h   v1.34.7
pe-kind-worker          Ready    worker          19h   v1.34.7
```

Nodes router status:
```shell
$ kubectl -n openperouter-system get routernodeconfigurationstatus
NAME                   READY   DEGRADED    AGE   
pe-kind-control-plane  True    False       19h
pe-kind-worker         True    False       19h   
```

```yaml
apiVersion: openpe.openperouter.github.io/v1alpha1
kind: RouterNodeConfigurationStatus
metadata:
  name: pe-kind-worker 
  namespace: openperouter-system
  ownerReferences:
  - apiVersion: v1
    kind: Node
    name: pe-kind-worker 
    uid: "e18de421-403c-4593-8787-8da99199ac2e"
status:
  conditions:
  - type: Ready
    status: "True"
    reason: ConfigurationSuccessful
    message: "All configuration applied successfully"
    lastTransitionTime: "2026-05-19T10:30:00Z"
  - type: Degraded
    status: "False"
    reason: ConfigurationSuccessful
    message: "All configuration are healthy"
    lastTransitionTime: "2026-05-19T10:30:00Z"
```

### Lifecycle
As soon the configuration controller is up, it will create RouterNodeConfigurationStatus CR per each node.
When a node is removed, the associated CR is garbage collected.
