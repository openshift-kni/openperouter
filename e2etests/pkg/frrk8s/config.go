// SPDX-License-Identifier:Apache-2.0

package frrk8s

import (
	frrk8sapi "github.com/metallb/frr-k8s/api/v1beta1"
	"github.com/openperouter/openperouter/api/v1alpha1"
	"github.com/openperouter/openperouter/e2etests/pkg/k8s"
	"github.com/openperouter/openperouter/e2etests/pkg/openperouter"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clientset "k8s.io/client-go/kubernetes"
)

var (
	Namespace           = "frr-k8s-system"
	frrk8sLabelSelector = "app=frr-k8s"
)

// ConfigFromVNI converts a VNI object to a FRRConfiguration object.
func ConfigFromVNI(vni v1alpha1.VNI) (frrk8sapi.FRRConfiguration, error) {
	routerIP, err := openperouter.RouterIPFromCIDR(vni.Spec.LocalCIDR)
	if err != nil {
		return frrk8sapi.FRRConfiguration{}, err
	}

	return frrk8sapi.FRRConfiguration{
		ObjectMeta: metav1.ObjectMeta{
			Name:      vni.Name,
			Namespace: Namespace,
		},
		Spec: frrk8sapi.FRRConfigurationSpec{
			BGP: frrk8sapi.BGPConfig{
				Routers: []frrk8sapi.Router{
					{
						ASN: *vni.Spec.HostASN,
						Neighbors: []frrk8sapi.Neighbor{
							{
								ASN:     vni.Spec.ASN,
								Address: routerIP,
								ToReceive: frrk8sapi.Receive{
									Allowed: frrk8sapi.AllowedInPrefixes{
										Mode: frrk8sapi.AllowAll,
									},
								},
							},
						},
					},
				},
			},
		},
	}, nil
}

func Pods(cs clientset.Interface) ([]*corev1.Pod, error) {
	return k8s.PodsForLabel(cs, Namespace, frrk8sLabelSelector)
}
