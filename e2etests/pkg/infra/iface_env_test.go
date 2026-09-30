// SPDX-License-Identifier:Apache-2.0

package infra

import (
	"testing"
)

func TestUnderlayIfaceDefaults(t *testing.T) {
	t.Setenv(EnvUnderlayIface, "")
	t.Setenv(EnvUnderlayIface2, "")
	if UnderlayIface1() != "toswitch1" {
		t.Fatalf("default iface1 = %q, want toswitch1", UnderlayIface1())
	}
	if UnderlayIface2() != "toswitch2" {
		t.Fatalf("default iface2 = %q, want toswitch2", UnderlayIface2())
	}
}

func TestUnderlayIfaceEnvOverride(t *testing.T) {
	t.Setenv(EnvUnderlayIface, "ens8f0np0")
	t.Setenv(EnvUnderlayIface2, "ens8f1np1")
	if UnderlayIface1() != "ens8f0np0" {
		t.Fatalf("iface1 = %q, want ens8f0np0", UnderlayIface1())
	}
	if UnderlayIface2() != "ens8f1np1" {
		t.Fatalf("iface2 = %q, want ens8f1np1", UnderlayIface2())
	}
}
