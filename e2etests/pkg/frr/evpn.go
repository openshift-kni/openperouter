// SPDX-License-Identifier:Apache-2.0

package frr

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/openperouter/openperouter/e2etests/pkg/executor"
)

func EVPNInfo(exec executor.Executor) (EVPNData, error) {
	res, err := exec.Exec("vtysh", "-c", "show bgp l2vpn evpn json")
	if err != nil {
		return EVPNData{}, errors.Join(err, errors.New("Failed to query l2vpn evpn"))
	}

	evpnInfo, err := parseL2VPNEVPN([]byte(res))
	if err != nil {
		return EVPNData{}, errors.Join(err, fmt.Errorf("Failed to parse l2vpn evpn: %w", err))
	}
	return evpnInfo, nil
}

type EVPNData struct {
	BgpTableVersion  int       `json:"bgpTableVersion"`
	BgpLocalRouterId string    `json:"bgpLocalRouterId"`
	DefaultLocPrf    int       `json:"defaultLocPrf"`
	LocalAS          int       `json:"localAS"`
	Entries          []RdEntry `json:"-"` // handled manually
	NumPrefix        int       `json:"numPrefix"`
	TotalPrefix      int       `json:"totalPrefix"`
}

// ContainsType5Route tells if the given prefix is received as type 5 route
// with the given vtep as next hop.
func (e *EVPNData) ContainsType5Route(prefix string, vtep string) bool {
	for _, entry := range e.Entries {
		for _, prefixEntry := range entry.Prefixes {
			for _, path := range prefixEntry.Paths {
				if path.IP == prefix {
					for _, n := range path.Nexthops {
						if n.IP == vtep {
							return true
						}
					}
				}
			}
		}
	}
	return false
}

type RdEntry struct {
	RD       string            `json:"rd"`
	Prefixes map[string]Prefix `json:"-"` // handled manually
}

type ExtendedCommunity struct {
	String string `json:"string"`
}

type Nexthop struct {
	IP       string `json:"ip"`
	Hostname string `json:"hostname"`
	Afi      string `json:"afi"`
	Used     bool   `json:"used"`
}

type Path struct {
	Valid             bool              `json:"valid"`
	Bestpath          bool              `json:"bestpath"`
	SelectionReason   string            `json:"selectionReason"`
	PathFrom          string            `json:"pathFrom"`
	RouteType         int               `json:"routeType"`
	EthTag            int               `json:"ethTag"`
	IPLen             int               `json:"ipLen"`
	IP                string            `json:"ip"`
	Metric            int               `json:"metric"`
	Weight            int               `json:"weight"`
	PeerId            string            `json:"peerId"`
	Path              string            `json:"path"`
	Origin            string            `json:"origin"`
	ExtendedCommunity ExtendedCommunity `json:"extendedCommunity"`
	Nexthops          []Nexthop         `json:"nexthops"`
}

type Prefix struct {
	Prefix    string `json:"prefix"`
	PrefixLen int    `json:"prefixLen"`
	Paths     []Path `json:"paths"`
}

func parseL2VPNEVPN(data []byte) (EVPNData, error) {
	res := EVPNData{
		Entries: make([]RdEntry, 0),
	}

	if err := json.Unmarshal(data, &res); err != nil {
		return EVPNData{}, fmt.Errorf("error unmarshalling JSON: %v", err)
	}

	var dynamicData map[string]json.RawMessage
	if err := json.Unmarshal(data, &dynamicData); err != nil {
		return EVPNData{}, fmt.Errorf("error unmarshalling JSON: %v", err)
	}

	for k, v := range dynamicData {
		if strings.Contains(k, ":") { // Route Distinguisher
			entry := RdEntry{
				RD:       k,
				Prefixes: make(map[string]Prefix),
			}

			var rd map[string]json.RawMessage
			if err := json.Unmarshal(v, &rd); err != nil {
				return EVPNData{}, fmt.Errorf("error unmarshalling JSON: %v", err)
			}

			for k, v := range rd {
				if strings.Contains(k, ":") { // Route
					var prefix Prefix
					if err := json.Unmarshal(v, &prefix); err != nil {
						return EVPNData{}, fmt.Errorf("error unmarshalling JSON: %v", err)
					}
					entry.Prefixes[k] = prefix
				}
			}

			res.Entries = append(res.Entries, entry)
		}
	}

	return res, nil
}
