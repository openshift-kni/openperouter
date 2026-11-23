// SPDX-License-Identifier:Apache-2.0

package grout

import (
	"context"
	"testing"

	"github.com/openperouter/openperouter/internal/grout/devicestate"
	"github.com/openperouter/openperouter/internal/hostnetwork"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/sys/unix"
)

func TestSetupTunnelEndpointRequiresAddress(t *testing.T) {
	err := setupTunnelEndpoint(context.Background(), NewClient("sock"), hostnetwork.UnderlayTunnelEndpointParams{})
	require.ErrorContains(t, err, "at least one tunnel endpoint IP must be provided")
}

func TestUnderlayInterfaces(t *testing.T) {
	store := devicestate.Store{Dir: t.TempDir()}
	require.NoError(t, store.Save("eth0", devicestate.State{InterfaceName: "eth0"}))
	require.NoError(t, store.Save("ens1f0", devicestate.State{InterfaceName: "ens1f0", PCIAddress: testPCIAddr}))

	got, err := UnderlayInterfaces(store)
	require.NoError(t, err)
	assert.ElementsMatch(t, []hostnetwork.UnderlayInterface{
		{InterfaceName: "eth0", Kind: hostnetwork.UnderlayInterfaceNetDev},
		{InterfaceName: "ens1f0", Kind: hostnetwork.UnderlayInterfaceNetDev},
	}, got)
}

func TestUnderlayTAPKernelName(t *testing.T) {
	t.Parallel()

	// Direct path when tap_<underlay> fits.
	assert.Equal(t, "tap_eth0", UnderlayTAPKernelName("eth0"))
	assert.Equal(t, "tap_e0.175", UnderlayTAPKernelName("e0.175"))
	assert.Equal(t, "tap_e1.176", UnderlayTAPKernelName("e1.176"))
	assert.Equal(t, "tap_ens1f0.175", UnderlayTAPKernelName("ens1f0.175"))

	// Exact hashed fixture: readable PCI head + 4-char SHA-256 + VLAN.
	assert.Equal(t, "tap_1f0a241.175", UnderlayTAPKernelName("ens1f0np0.175"))
	assert.NotEqual(t, UnderlayTAPKernelName("ens1f0np0.175"), UnderlayTAPKernelName("ens1f0np1.175"))

	// All-letter names too long for direct path.
	a := UnderlayTAPKernelName("abcdefghijklm")
	b := UnderlayTAPKernelName("abcdefghijkzz")
	assert.NotEqual(t, a, b)

	// Length limit.
	for _, name := range []string{
		"ens1f0np0.175",
		"ens1f0.175",
		"e0.175",
		"enp3s0f0v0.175",
		"abcdefghijklm",
	} {
		require.Less(t, len(UnderlayTAPKernelName(name)), unix.IFNAMSIZ, name)
	}

	// Long enp-style names.
	enpA := "enp3s0f0v0.175"
	enpB := "enp3s0f0v1.175"
	gotA := UnderlayTAPKernelName(enpA)
	gotB := UnderlayTAPKernelName(enpB)
	assert.GreaterOrEqual(t, len(underlayTAPKernelNamePrefix+enpA), unix.IFNAMSIZ)
	assert.NotEqual(t, gotA, gotB)

	// Duplicate detection (short hash can still collide in theory).
	require.NoError(t, ValidateUnderlayTAPKernelNamesUnique([]string{"e0.175", "e1.176"}))
	require.NoError(t, ValidateUnderlayTAPKernelNamesUnique([]string{"ens1f0np0.175", "ens1f1np1.176"}))
	require.Error(t, ValidateUnderlayTAPKernelNamesUnique([]string{"e0.175", "e0.175"}))
	assert.ErrorContains(t, ValidateUnderlayTAPKernelNamesUnique([]string{"e0.175", "e0.175"}),
		`share TAP kernel name "tap_e0.175"`)
}

func TestUnderlayPortOptions(t *testing.T) {
	queues, size := int32(4), int32(1024)
	iface := hostnetwork.UnderlayInterface{InterfaceName: "eth0", AcceleratedConfig: &hostnetwork.AcceleratedConfigParams{
		RXQueues: &queues, QSize: &size,
	}}
	assert.Equal(t, portOptions{RXQueues: &queues, QSize: &size},
		underlayPortOptions(iface))
	assert.Equal(t, portOptions{},
		underlayPortOptions(hostnetwork.UnderlayInterface{InterfaceName: "eth0"}))
}
