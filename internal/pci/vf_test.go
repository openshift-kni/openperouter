// SPDX-License-Identifier:Apache-2.0

package pci

import (
	"os"
	"path/filepath"
	"testing"
)

const testPFName = "enp3s0f0"

func TestResolvePCIAddress(t *testing.T) {
	s := Sysfs{Root: t.TempDir()}

	pciAddr := testPCIAddress
	deviceDir := filepath.Join(s.Root, "bus", "pci", "devices", pciAddr)
	if err := os.MkdirAll(deviceDir, 0o755); err != nil {
		t.Fatal(err)
	}

	if err := s.ResolvePCIAddress(pciAddr); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func TestResolvePCIAddress_InvalidFormat(t *testing.T) {
	if err := (Sysfs{}).ResolvePCIAddress("invalid"); err == nil {
		t.Fatal("expected error for invalid PCI address format")
	}
}

func TestResolvePCIAddress_DeviceNotFound(t *testing.T) {
	s := Sysfs{Root: t.TempDir()}

	if err := s.ResolvePCIAddress(testPCIAddress); err == nil {
		t.Fatal("expected error for missing PCI device")
	}
}

func TestResolvePFVFIndex(t *testing.T) {
	s := Sysfs{Root: t.TempDir()}

	pfName := testPFName
	vfIndex := 2
	expectedPCI := "0000:03:0a.0"

	virtfnDir := filepath.Join(s.Root, "class", "net", pfName, "device")
	if err := os.MkdirAll(virtfnDir, 0o755); err != nil {
		t.Fatal(err)
	}
	symlink := filepath.Join(virtfnDir, "virtfn2")
	if err := os.Symlink("../"+expectedPCI, symlink); err != nil {
		t.Fatal(err)
	}

	pciAddr, err := s.ResolvePFVFIndex(pfName, vfIndex)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if pciAddr != expectedPCI {
		t.Fatalf("expected %s, got %s", expectedPCI, pciAddr)
	}
}

func TestResolvePFVFIndex_MissingVF(t *testing.T) {
	s := Sysfs{Root: t.TempDir()}

	pfName := testPFName
	virtfnDir := filepath.Join(s.Root, "class", "net", pfName, "device")
	if err := os.MkdirAll(virtfnDir, 0o755); err != nil {
		t.Fatal(err)
	}

	if _, err := s.ResolvePFVFIndex(pfName, 99); err == nil {
		t.Fatal("expected error for missing VF symlink")
	}
}

func TestResolvePFVFIndex_InvalidTarget(t *testing.T) {
	s := Sysfs{Root: t.TempDir()}

	pfName := testPFName
	virtfnDir := filepath.Join(s.Root, "class", "net", pfName, "device")
	if err := os.MkdirAll(virtfnDir, 0o755); err != nil {
		t.Fatal(err)
	}
	symlink := filepath.Join(virtfnDir, "virtfn0")
	if err := os.Symlink("../not-a-pci-addr", symlink); err != nil {
		t.Fatal(err)
	}

	if _, err := s.ResolvePFVFIndex(pfName, 0); err == nil {
		t.Fatal("expected error for invalid symlink target")
	}
}
