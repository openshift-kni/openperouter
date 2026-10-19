// SPDX-License-Identifier:Apache-2.0

package grout

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"

	"github.com/openperouter/openperouter/internal/grout/devicestate"
	"github.com/openperouter/openperouter/internal/hostnetwork"
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

	pciAddr, err := resolveTrunkVFPCI(vfPair.TrunkVFName, store, sysfs)
	if err != nil {
		return fmt.Errorf("SetupL2VNI VF-pair: failed to resolve PCI address: %w", err)
	}
	trunkPortName := "t_" + vfPair.TrunkVFName

	if err := prepareAndBindTrunkVF(ctx, client, params.TargetNS, pciAddr, trunkPortName, sysfs); err != nil {
		return fmt.Errorf("SetupL2VNI VF-pair: failed to prepare trunk VF %s: %w", pciAddr, err)
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
// that are not referenced by any configured L2VNI.
func RemoveStaleVFPairResources(
	ctx context.Context,
	client *Client,
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
	return nil
}

// resolveTrunkVFPCI resolves the PCI address for the trunk VF netlink name,
// using a cached device state file when available.
func resolveTrunkVFPCI(netlinkName string, store devicestate.Store, sysfs pci.Sysfs) (string, error) {
	devState, err := store.Load(netlinkName)
	if err == nil {
		return devState.PCIAddress, nil
	}
	if !errors.Is(err, devicestate.ErrNotFound) {
		return "", fmt.Errorf("failed to load device state for %s: %w", netlinkName, err)
	}

	slog.Info("device state not found, resolving PCI address from netlink name", "netlinkName", netlinkName)
	pciAddr, err := sysfs.PCIAddressForNetlinkName(netlinkName)
	if err != nil {
		return "", fmt.Errorf("failed to resolve PCI address for %s: %w", netlinkName, err)
	}

	slog.Info("resolved PCI address from netlink name", "pciAddr", pciAddr)
	state := devicestate.State{
		InterfaceName: netlinkName,
		PCIAddress:    pciAddr,
	}
	if err := store.Save(state); err != nil {
		return "", fmt.Errorf("failed to save device state for %s: %w", netlinkName, err)
	}
	return pciAddr, nil
}

// PrepareAndBindTrunkVF prepares the DPDK driver for a trunk VF and creates
// the grout port for it. It is idempotent: calling it for a PCI address that
// is already bound is a no-op.
func prepareAndBindTrunkVF(
	ctx context.Context,
	client *Client,
	targetNS, pciAddr, portName string,
	sysfs pci.Sysfs,
) error {
	perouterNetNS, err := netns.GetFromPath(targetNS)
	if err != nil {
		return fmt.Errorf("failed to get namespace %s: %w", targetNS, err)
	}
	defer func() {
		if err := perouterNetNS.Close(); err != nil {
			slog.Error("failed to close namespace", "namespace", targetNS, "error", err)
		}
	}()

	if err := setupInterfaceForHWAcceleration(ctx, perouterNetNS, pciAddr, "", sysfs); err != nil {
		return fmt.Errorf("failed to prepare trunk VF driver for %s: %w", pciAddr, err)
	}

	return client.ensurePort(ctx, portName, portOptions{Devargs: pciAddr})
}
