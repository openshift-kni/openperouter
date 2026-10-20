// SPDX-License-Identifier:Apache-2.0

package grout

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"github.com/openperouter/openperouter/internal/grout/devicestate"
	"github.com/openperouter/openperouter/internal/hostnetwork"
	"github.com/openperouter/openperouter/internal/netnamespace"
	"github.com/openperouter/openperouter/internal/pci"
	"github.com/vishvananda/netns"
)

func setupL2VNIVFPair(
	ctx context.Context,
	client *Client,
	params hostnetwork.L2VNIParams,
	bridgeName string,
	store devicestate.Store,
	sysfs pci.Sysfs,
) error {
	vfPair := params.VFPair

	trunkPortName := "t_" + vfPair.TrunkVFName

	if err := prepareAndBindTrunkVF(ctx, client, params.TargetNS, vfPair.TrunkVFName, trunkPortName,
		store, sysfs); err != nil {
		return fmt.Errorf("SetupL2VNI VF-pair: failed to prepare trunk VF %s: %w", vfPair.TrunkVFName, err)
	}

	vlanIfName := VLANSubInterfaceName(vfPair.VLAN, trunkPortName)
	if err := client.ensureVLANSubInterface(ctx, vlanIfName, trunkPortName, vfPair.VLAN); err != nil {
		return fmt.Errorf("SetupL2VNI VF-pair: failed to create VLAN sub-interface: %w", err)
	}

	if err := client.ensureBridgeMember(ctx, "vlan", bridgeName, vlanIfName); err != nil {
		return fmt.Errorf("SetupL2VNI VF-pair: failed to attach VLAN %s to bridge %s: %w",
			vlanIfName, bridgeName, err)
	}

	if len(params.L2GatewayIPs) > 0 {
		if err := setupL2Gateway(ctx, client, bridgeName, params); err != nil {
			return fmt.Errorf("SetupL2VNI VF-pair: failed to setup L2 gateway: %w", err)
		}
	}

	if err := client.setPortUp(ctx, trunkPortName); err != nil {
		return fmt.Errorf("SetupL2VNI VF-pair: failed to bring up trunk port %s: %w", trunkPortName, err)
	}

	return nil
}

// VLANSubInterfaceName returns the grout VLAN sub-interface name for a given
// VLAN ID and trunk port name.
func VLANSubInterfaceName(vlan int32, trunkPortName string) string {
	return fmt.Sprintf("%s.%d", trunkPortName, vlan)
}

// RemoveStaleVFPairResources removes VLAN sub-interfaces and trunk ports
// that are not referenced by any configured L2VNI, then hands the trunk VFs
// no longer referenced back to the kernel as described by their saved
// device state.
func RemoveStaleVFPairResources(
	ctx context.Context,
	client *Client,
	targetNS string,
	configuredL2VNIs []hostnetwork.L2VNIParams,
	store devicestate.Store,
	sysfs pci.Sysfs,
) error {
	expectedVLANIfs := map[string]bool{}
	referencedTrunks := map[string]bool{}
	for _, l2 := range configuredL2VNIs {
		if l2.VFPair == nil {
			continue
		}
		trunkPortName := "t_" + l2.VFPair.TrunkVFName
		vlanIfName := VLANSubInterfaceName(l2.VFPair.VLAN, trunkPortName)
		expectedVLANIfs[vlanIfName] = true
		referencedTrunks[trunkPortName] = true
	}

	ifaces, err := client.listInterfaces(ctx)
	if err != nil {
		return fmt.Errorf("failed to list interfaces for VF-pair cleanup: %w", err)
	}

	for _, iface := range ifaces {
		if !strings.HasPrefix(iface.Name, "t_") || !strings.Contains(iface.Name, ".") {
			continue
		}
		if expectedVLANIfs[iface.Name] {
			continue
		}
		slog.InfoContext(ctx, "removing stale VLAN sub-interface", "name", iface.Name)
		if err := client.deleteInterface(ctx, iface.Name); err != nil {
			return fmt.Errorf("failed to delete stale VLAN sub-interface %s: %w", iface.Name, err)
		}
	}

	for _, iface := range ifaces {
		if !strings.HasPrefix(iface.Name, "t_") || strings.Contains(iface.Name, ".") {
			continue
		}
		if referencedTrunks[iface.Name] {
			continue
		}
		slog.InfoContext(ctx, "removing stale trunk port", "name", iface.Name)
		if err := client.deletePort(ctx, iface.Name); err != nil {
			return fmt.Errorf("failed to delete stale trunk port %s: %w", iface.Name, err)
		}
	}

	return restoreStaleTrunkVFs(ctx, targetNS, referencedTrunks, store, sysfs)
}

// prepareAndBindTrunkVF prepares the DPDK driver for a trunk VF and creates
// the grout port for it. It is idempotent: calling it for a trunk VF that
// is already bound is a no-op, so several L2VNIs can share the same trunk VF.
func prepareAndBindTrunkVF(
	ctx context.Context,
	client *Client,
	targetNS, netdev, portName string,
	store devicestate.Store,
	sysfs pci.Sysfs,
) error {
	state, err := ensureDeviceState(netdev, PortModeAccelerated, store, sysfs)
	if err != nil {
		return err
	}

	perouterNetNS, err := netns.GetFromPath(targetNS)
	if err != nil {
		return fmt.Errorf("failed to get namespace %s: %w", targetNS, err)
	}
	defer func() {
		if err := perouterNetNS.Close(); err != nil {
			slog.Error("failed to close namespace", "namespace", targetNS, "error", err)
		}
	}()

	if err := setupInterfaceForHWAcceleration(ctx, perouterNetNS, state.PCIAddress, netdev, sysfs); err != nil {
		return fmt.Errorf("failed to prepare trunk VF driver for %s: %w", state.PCIAddress, err)
	}

	if err := client.ensurePort(ctx, portName, portOptions{Devargs: state.PCIAddress}); err != nil {
		return fmt.Errorf("failed to create grout trunk port %s: %w", portName, err)
	}

	if !pci.IsBifurcated(state.OriginalDriver) {
		return nil
	}
	return netnamespace.In(perouterNetNS, func() error {
		return quiesceBifurcatedNetdev(netdev)
	})
}

// restoreStaleTrunkVFs hands the trunk VFs whose grout port is not
// referenced anymore back to the kernel. The device state is deleted last, so
// an interrupted restore is resumed by the next call.
func restoreStaleTrunkVFs(
	ctx context.Context,
	targetNS string,
	referencedTrunks map[string]bool,
	store devicestate.Store,
	sysfs pci.Sysfs,
) error {
	states, err := store.List()
	if err != nil {
		return fmt.Errorf("failed to list saved trunk VF states: %w", err)
	}
	for _, state := range states {
		if referencedTrunks["t_"+state.InterfaceName] {
			continue
		}
		slog.InfoContext(ctx, "restoring stale trunk VF", "name", state.InterfaceName, "pciAddress", state.PCIAddress)
		if err := restoreAcceleratedDevice(ctx, targetNS, state, sysfs); err != nil {
			return fmt.Errorf("failed to restore trunk VF %s: %w", state.InterfaceName, err)
		}
		if err := store.Delete(state.InterfaceName); err != nil {
			return fmt.Errorf("failed to delete device state for trunk VF %s: %w", state.InterfaceName, err)
		}
	}
	return nil
}
