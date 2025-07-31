---
weight: 50
title: "Examples"
description: "Integration examples with BGP-speaking components"
icon: "article"
date: "2025-06-15T15:03:22+02:00"
lastmod: "2025-06-15T15:03:22+02:00"
toc: true
---

This section provides practical examples of integrating OpenPERouter with various BGP-speaking components commonly used in Kubernetes environments.

## Overview

OpenPERouter behaves exactly like a physical Provider Edge (PE) router, enabling seamless integration with any BGP-speaking component. This router-like behavior ensures that integration is straightforward and follows standard BGP peering practices.

## Prerequisites

All examples in this section assume you have:

- OpenPERouter installed and configured (see [Installation]({{< ref "installation" >}}))
- A [development environment]({{< ref "../contributing/devenv.md" >}}) with two L3 VNIs available from the fabric
- Basic understanding of BGP and EVPN concepts

## Development Environment Setup

The examples use a development environment with the following topology:

![](/images/openpedevenv.svg)

This environment provides:

- Two L3 VNIs (100 and 200) configured in the fabric
- Leaf switches (leafA and leafB) with BGP peering
- A kind cluster for testing OpenPERouter integration

## Base OpenPERouter Configuration

Before running any integration examples, you need to configure OpenPERouter with the appropriate underlay and VNI settings.

### Underlay Configuration

Configure the underlay to peer with the `kind-leaf` node:

```yaml
apiVersion: openpe.openperouter.github.io/v1alpha1
kind: Underlay
metadata:
  name: underlay
  namespace: openperouter-system
spec:
  asn: 64514
  vtepcidr: 100.65.0.0/24
  nics:
    - toswitch
  neighbors:
    - asn: 64512
      address: 192.168.11.2
```

**Configuration Details:**

- **ASN**: 64514 (OpenPERouter's ASN)
- **VTEP CIDR**: 100.65.0.0/24 (VTEP IP allocation range)
- **Interface**: `toswitch` (network interface to the fabric)
- **Neighbor**: 192.168.11.2 with ASN 64512 (kind-leaf node)

### VNI Configurations

Create two VNIs that match the fabric configuration:

```yaml
# Red VNI (VNI 100)
apiVersion: openpe.openperouter.github.io/v1alpha1
kind: L3VNI
metadata:
  name: red
  namespace: openperouter-system
spec:
  asn: 64514
  vni: 100
  localcidr:
    ipv4: 192.169.10.0/24
  hostasn: 64515
---
# Blue VNI (VNI 200)
apiVersion: openpe.openperouter.github.io/v1alpha1
kind: L3VNI
metadata:
  name: blue
  namespace: openperouter-system
spec:
  asn: 64514
  vni: 200
  localcidr:
    ipv4: 192.169.11.0/24
  hostasn: 64515
```

**VNI Details:**

- **Red VNI**: VNI 100 with CIDR 192.169.10.0/24
- **Blue VNI**: VNI 200 with CIDR 192.169.11.0/24
- **Host ASN**: 64515 (for BGP sessions with host components)

## Available Examples

### MetalLB Integration

Learn how to integrate OpenPERouter with MetalLB to advertise LoadBalancer services across the EVPN fabric.

**Key Features:**

- LoadBalancer service advertisement
- EVPN Type 5 route generation
- Cross-fabric service reachability

[View MetalLB Integration Example →]({{< ref "metallb" >}})
