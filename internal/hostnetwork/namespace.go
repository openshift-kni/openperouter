// SPDX-License-Identifier:Apache-2.0

package hostnetwork

import (
	"fmt"
	"log/slog"
	"runtime"

	"github.com/vishvananda/netns"
)

// inNamespace execs the provided function in the given network
// namespace.
func inNamespace(ns netns.NsHandle, execInNamespace func() error) error {
	// required as a change of context might wake up the goroutine
	// in a different thread.
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	origns, err := netns.Get()
	if err != nil {
		return fmt.Errorf("setupUnderlay: Failed to get current network namespace")
	}
	defer func() {
		if err := origns.Close(); err != nil {
			slog.Error("failed to default namespace", "error", err)
		}
	}()

	if err := netns.Set(ns); err != nil {
		return fmt.Errorf("setupUnderlay: Failed to set current network namespace to %s", ns.String())
	}

	defer func() {
		if err := netns.Set(origns); err != nil {
			slog.Error("failed to set default namespace", "error", err)
		}
	}()

	if err := execInNamespace(); err != nil {
		return err
	}
	return nil
}
