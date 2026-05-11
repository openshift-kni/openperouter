// SPDX-License-Identifier:Apache-2.0

package routerconfiguration

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestHandleNonRecoverableErrorRemovesFRRConfig(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "frr.conf")
	if err := os.WriteFile(configPath, []byte("router bgp 64512"), 0600); err != nil {
		t.Fatal(err)
	}

	r := &RouterNamedNS{
		manager: &RouterNamedNSProvider{
			FRRConfigPath: configPath,
		},
	}

	if err := r.HandleNonRecoverableError(context.Background()); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(configPath); !os.IsNotExist(err) {
		t.Fatalf("expected frr.conf to be removed, got err: %v", err)
	}
}

func TestHandleNonRecoverableErrorNoConfigPath(t *testing.T) {
	r := &RouterNamedNS{
		manager: &RouterNamedNSProvider{},
	}

	if err := r.HandleNonRecoverableError(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestHandleNonRecoverableErrorMissingFile(t *testing.T) {
	r := &RouterNamedNS{
		manager: &RouterNamedNSProvider{
			FRRConfigPath: "/tmp/nonexistent-frr-config-test.conf",
		},
	}

	if err := r.HandleNonRecoverableError(context.Background()); err != nil {
		t.Fatal(err)
	}
}
