/*
Copyright 2024.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	LinuxBridge = "linux-bridge"
	OVSBridge   = "ovs-bridge"

	// RoutingDomainTypeL3VNI selects an L3VNI as the routing domain provider.
	RoutingDomainTypeL3VNI = "L3VNI"

	// RoutingDomainTypeL3VPN selects an L3VPN as the routing domain provider.
	RoutingDomainTypeL3VPN = "L3VPN"
)

// L2VNISpec defines the desired state of VNI.
// +kubebuilder:validation:XValidation:rule="!has(self.gatewayIPs) || size(self.gatewayIPs) == 0 || has(self.routingDomain)",message="gatewayIPs cannot be set without routingDomain"
// +kubebuilder:validation:XValidation:rule="!(has(self.hostmaster) && has(self.sriovVFPair))",message="hostmaster and sriovVFPair are mutually exclusive"
type L2VNISpec struct {
	// nodeSelector specifies which nodes this L2VNI applies to.
	// If empty or not specified, applies to all nodes.
	// Multiple L2VNIs can match the same node.
	// +optional
	NodeSelector *metav1.LabelSelector `json:"nodeSelector,omitempty"`

	// routingDomain optionally attaches this L2VNI to a routing domain
	// provided by a backing resource (L3VNI or L3VPN). When omitted, the
	// L2VNI is a disconnected overlay (east-west L2 only, no VRF, no
	// gateway).
	// +optional
	RoutingDomain *RoutingDomain `json:"routingDomain,omitempty"`

	// vni is the VXLan VNI to be used
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=16777215
	// +required
	VNI int32 `json:"vni,omitempty"`

	// vxlanport is the port to be used for VXLan encapsulation.
	// +default=4789
	// +optional
	VXLanPort *int32 `json:"vxlanport,omitempty"`

	// underlayAddressFamily selects which VTEP address family to use for this VNI's
	// VXLAN interface. When omitted, defaults to the available family in the underlay
	// (IPv4 preferred in dual-stack).
	// +kubebuilder:validation:Enum=ipv4;ipv6
	// +optional
	UnderlayAddressFamily *string `json:"underlayAddressFamily,omitempty"`

	// hostmaster is the interface on the host the veth should be attached to.
	// If not set, the host veth will not be attached to any interface and it must be
	// attached manually (or by some other means). This is useful if another controller
	// is leveraging the host interface for the VNI.
	// Mutually exclusive with sriovVFPair.
	// +optional
	HostMaster *HostMaster `json:"hostmaster,omitempty"`

	// sriovVFPair enables SR-IOV VF-to-VF communication for this L2VNI,
	// replacing the host bridge and TAP/veth pair with direct VF binding.
	// The specified trunk VF is bound to grout as a DPDK port. Workloads
	// connect via other VFs on the same PF, tagged with the specified VLAN.
	// The NIC's embedded switch handles local VF-to-VF forwarding; grout
	// handles VXLAN encap/decap for remote nodes.
	// Only valid when grout is enabled. Mutually exclusive with hostmaster.
	// +optional
	SRIOVVFPair *SRIOVVFPairConfig `json:"sriovVFPair,omitempty"`

	// gatewayIPs is a list of IP addresses in CIDR notation for the
	// distributed anycast gateway on this L2 segment's bridge
	// (Integrated Routing and Bridging interface). It is a property of
	// the L2 segment itself, so it lives on the L2VNI rather than
	// inside the routing-domain reference.
	// Maximum of 2 addresses are allowed. If 2 addresses are provided, one must be IPv4 and one must be IPv6.
	// +optional
	// +kubebuilder:validation:MaxItems=2
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="GatewayIPs cannot be changed"
	// +listType=atomic
	GatewayIPs []string `json:"gatewayIPs,omitempty"`
}

// RoutingDomain is a discriminated union over the resource kinds that can
// provide a routing domain. Exactly one sub-struct must match the type
// discriminator.
// +union
// +kubebuilder:validation:XValidation:rule="self.type != 'L3VNI' || (has(self.l3vni) && !has(self.l3vpn))",message="type L3VNI requires l3vni to be set and l3vpn to be unset"
// +kubebuilder:validation:XValidation:rule="self.type != 'L3VPN' || (has(self.l3vpn) && !has(self.l3vni))",message="type L3VPN requires l3vpn to be set and l3vni to be unset"
type RoutingDomain struct {
	// type selects the kind of resource that provides this routing domain.
	// +kubebuilder:validation:Enum=L3VNI;L3VPN
	// +required
	// +unionDiscriminator
	Type string `json:"type,omitempty"`

	// l3vni references the L3VNI (metadata.name) in the same namespace that
	// provides the routing domain for this L2VNI.
	// +optional
	L3VNI *L3VNIReference `json:"l3vni,omitempty"`

	// l3vpn references the L3VPN (metadata.name) in the same namespace that
	// provides the routing domain for this L2VNI.
	// +optional
	L3VPN *L3VPNReference `json:"l3vpn,omitempty"`
}

// L3VNIReference references an L3VNI by name.
type L3VNIReference struct {
	// name is the metadata.name of the L3VNI in the same namespace.
	// +kubebuilder:validation:MinLength=1
	// +required
	Name string `json:"name,omitempty"`
}

// L3VPNReference references an L3VPN by name.
type L3VPNReference struct {
	// name is the metadata.name of the L3VPN in the same namespace.
	// +kubebuilder:validation:MinLength=1
	// +required
	Name string `json:"name,omitempty"`
}

// LinuxBridgeConfig contains configuration for Linux bridge type.
// +kubebuilder:validation:XValidation:rule="(self.?name.orValue(\"\") != \"\") != self.?autoCreate.orValue(false)",message="either name must be set or autoCreate must be true, but not both."
type LinuxBridgeConfig struct {
	// name of the Linux bridge interface.
	// +kubebuilder:validation:Pattern=`^[a-zA-Z][a-zA-Z0-9_-]*$`
	// +kubebuilder:validation:MaxLength=15
	// +optional
	Name *string `json:"name,omitempty"`

	// autoCreate determines if the bridge should be created automatically.
	// When true, the bridge is created with name br-hs-<VNI>.
	// +default=false
	// +optional
	AutoCreate *bool `json:"autoCreate,omitempty"`
}

// OVSBridgeConfig contains configuration for OVS bridge type.
// +kubebuilder:validation:XValidation:rule="(self.?name.orValue(\"\") != \"\") != self.?autoCreate.orValue(false)",message="either name must be set or autoCreate must be true, but not both."
type OVSBridgeConfig struct {
	// name of the OVS bridge interface.
	// +kubebuilder:validation:Pattern=`^[a-zA-Z][a-zA-Z0-9_-]*$`
	// +kubebuilder:validation:MaxLength=15
	// +optional
	Name *string `json:"name,omitempty"`

	// autoCreate determines if the OVS bridge should be created automatically.
	// When true, the bridge is created with name br-hs-<VNI>.
	// +default=false
	// +optional
	AutoCreate *bool `json:"autoCreate,omitempty"`
}

// +kubebuilder:validation:XValidation:rule="(self.type == 'linux-bridge' && has(self.linuxBridge) && !has(self.ovsBridge)) || (self.type == 'ovs-bridge' && has(self.ovsBridge) && !has(self.linuxBridge))",message="type/config mismatch: 'linux-bridge' requires linuxBridge field, 'ovs-bridge' requires ovsBridge field"
type HostMaster struct {
	// type of the host interface. Supported values: "linux-bridge", "ovs-bridge".
	// +kubebuilder:validation:Enum=linux-bridge;ovs-bridge
	// +required
	Type string `json:"type,omitempty"`

	// linuxBridge configuration. Must be set when Type is "linux-bridge".
	// +optional
	LinuxBridge *LinuxBridgeConfig `json:"linuxBridge,omitempty"`

	// ovsBridge configuration. Must be set when Type is "ovs-bridge".
	// +optional
	OVSBridge *OVSBridgeConfig `json:"ovsBridge,omitempty"`
}

// SRIOVVFPairConfig specifies the SR-IOV trunk VF and VLAN for VF-to-VF
// communication on an L2VNI.
// Exactly one VF selector must be used: either pciAddress alone, or pfName +
// vfIndex together.
// +kubebuilder:validation:XValidation:rule="has(self.pciAddress) != (has(self.pfName) && has(self.vfIndex))",message="specify either pciAddress or both pfName and vfIndex, not both"
// +kubebuilder:validation:XValidation:rule="!has(self.pfName) || has(self.vfIndex)",message="vfIndex is required when pfName is set"
// +kubebuilder:validation:XValidation:rule="!has(self.vfIndex) || has(self.pfName)",message="pfName is required when vfIndex is set"
type SRIOVVFPairConfig struct {
	// pciAddress is the PCI Bus:Device.Function address of the trunk VF to
	// bind to grout (e.g. "0000:03:02.0"). The trunk VF must have no VLAN
	// configured (VLAN 0) so it receives all tagged frames from other VFs.
	// Mutually exclusive with pfName/vfIndex.
	// +kubebuilder:validation:Pattern=`^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$`
	// +optional
	PCIAddress *string `json:"pciAddress,omitempty"`

	// pfName is the name of the Physical Function whose VF will be the
	// trunk port. Must be used together with vfIndex.
	// Mutually exclusive with pciAddress.
	// +kubebuilder:validation:Pattern=`^[a-zA-Z][a-zA-Z0-9._-]*$`
	// +kubebuilder:validation:MaxLength=15
	// +optional
	PFName *string `json:"pfName,omitempty"`

	// vfIndex is the index of the Virtual Function on the PF to use as
	// the trunk port. Must be used together with pfName.
	// Mutually exclusive with pciAddress.
	// +kubebuilder:validation:Minimum=0
	// +optional
	VFIndex *int `json:"vfIndex,omitempty"`

	// vlan is the 802.1Q VLAN ID that maps to this L2VNI. Workload VFs
	// on the same PF configured with this VLAN ID will participate in
	// this L2VNI's VXLAN overlay.
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=4094
	// +required
	VLAN int32 `json:"vlan"`

	// portOptions specifies optional DPDK port parameters for the trunk VF.
	// +optional
	PortOptions *GroutPortOptions `json:"portOptions,omitempty"`
}

// VNIStatus defines the observed state of VNI.
type L2VNIStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:webhook:verbs=create;update,path=/validate-openperouter-io-v1alpha1-l2vni,mutating=false,failurePolicy=fail,groups=network.openperouter.io,resources=l2vnis,versions=v1alpha1,name=l2vnivalidationwebhook.openperouter.io,sideEffects=None,admissionReviewVersions=v1

// L2VNI represents a VXLan VNI to receive EVPN type 2 routes
// from.
type L2VNI struct {
	metav1.TypeMeta `json:",inline"`
	// metadata is the standard object metadata.
	// +optional
	metav1.ObjectMeta `json:"metadata"`

	// spec defines the desired state of L2VNI.
	// +required
	Spec L2VNISpec `json:"spec,omitzero"`
	// status defines the observed state of L2VNI.
	// +optional
	Status *L2VNIStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// VNIList contains a list of VNI.
type L2VNIList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata"`
	Items           []L2VNI `json:"items"`
}
