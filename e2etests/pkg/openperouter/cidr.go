// SPDX-License-Identifier:Apache-2.0

package openperouter

import (
	"fmt"
	"net"

	gocidr "github.com/apparentlymart/go-cidr/cidr"
)

func RouterIPFromCIDR(cidr string) (string, error) {
	_, vtepCIDR, err := net.ParseCIDR(cidr)
	if err != nil {
		return "", fmt.Errorf("failed to parse cidr %s: %w", cidr, err)
	}
	ip, err := gocidr.Host(vtepCIDR, 0)
	if err != nil {
		return "", fmt.Errorf("failed to get index %d from cidr %s", 1, vtepCIDR)
	}
	return ip.String(), nil
}
