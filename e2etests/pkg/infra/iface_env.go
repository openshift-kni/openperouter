// SPDX-License-Identifier:Apache-2.0

package infra

import "os"

const (
	// EnvUnderlayIface is the host NetworkDevice name used in Underlay CRs
	// for the primary toswitch path (default: toswitch1). Set this on
	// baremetal/bastion clusters to the real secondary NIC (e.g. ens8f0np0)
	// so tests do not require renaming the interface.
	EnvUnderlayIface = "OPENPE_UNDERLAY_IFACE"

	// EnvUnderlayIface2 is the optional second underlay NIC (default: toswitch2).
	EnvUnderlayIface2 = "OPENPE_UNDERLAY_IFACE2"

	defaultUnderlayIface  = "toswitch1"
	defaultUnderlayIface2 = "toswitch2"
)

// UnderlayIface1 returns the primary underlay host interface name.
func UnderlayIface1() string {
	if v := os.Getenv(EnvUnderlayIface); v != "" {
		return v
	}
	return defaultUnderlayIface
}

// UnderlayIface2 returns the secondary underlay host interface name.
func UnderlayIface2() string {
	if v := os.Getenv(EnvUnderlayIface2); v != "" {
		return v
	}
	return defaultUnderlayIface2
}

// UnderlayIfaces returns both underlay host interface names (primary, secondary).
func UnderlayIfaces() []string {
	return []string{UnderlayIface1(), UnderlayIface2()}
}
