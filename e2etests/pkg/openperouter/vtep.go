// SPDX-License-Identifier:Apache-2.0

package openperouter

import (
	"fmt"
	"net"
	"strconv"

	gocidr "github.com/apparentlymart/go-cidr/cidr"
	"github.com/openperouter/openperouter/api/v1alpha1"
	"github.com/openperouter/openperouter/e2etests/pkg/ipfamily"
	corev1 "k8s.io/api/core/v1"
)

const nodeIndexAnnotation = "openpe.io/nodeindex"

func GetVtepIPv4ForNode(tunnelEndpoint *v1alpha1.TunnelEndpointConfig, node *corev1.Node) (string, error) {
	if node.Annotations == nil ||
		node.Annotations[nodeIndexAnnotation] == "" {
		return "", fmt.Errorf("no index for node %s", node.Name)
	}
	nodeIndex, err := strconv.Atoi(node.Annotations[nodeIndexAnnotation])
	if err != nil {
		return "", fmt.Errorf("non int index %s for node %s", node.Annotations[nodeIndexAnnotation], node.Name)
	}

	if tunnelEndpoint == nil {
		return "", fmt.Errorf("invalid nil tunnel endpoint")
	}
	cidr := ""
	for _, c := range tunnelEndpoint.CIDRs {
		if ipfamily.ForCIDRString(c) != ipfamily.IPv4 {
			continue
		}
		cidr = c
		break
	}
	if cidr == "" {
		return "", fmt.Errorf("GetVtepIPv4ForNode: no IPv4 CIDR found in %v", tunnelEndpoint.CIDRs)
	}

	_, vtepCIDR, err := net.ParseCIDR(cidr)
	if err != nil {
		return "", fmt.Errorf("failed to parse cidr %s: %w", cidr, err)
	}

	ip, err := gocidr.Host(vtepCIDR, nodeIndex)
	if err != nil {
		return "", fmt.Errorf("failed to get index %d from cidr %s", nodeIndex, vtepCIDR)
	}
	netip := net.IPNet{
		IP:   ip,
		Mask: net.CIDRMask(32, 32),
	}
	return netip.String(), nil
}
