// SPDX-License-Identifier:Apache-2.0

package routerconfiguration

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	k8serr "k8s.io/apimachinery/pkg/api/errors"

	"sigs.k8s.io/controller-runtime/pkg/client"
	ctrlutil "sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	"github.com/openperouter/openperouter/api/v1alpha1"
)

// reconcileNodeStatus creates or updates the node status resource.
// It sets the owner reference to the hosting node.
func (r *PERouterReconciler) reconcileNodeStatus(ctx context.Context) error {
	node := &corev1.Node{}
	if err := r.Get(ctx, client.ObjectKey{Name: r.MyNode}, node); err != nil {
		if k8serr.IsNotFound(err) {
			return fmt.Errorf("unexpected error: hosting node not found: %w", err)
		}
		return fmt.Errorf("failed to get hosting node: %w", err)
	}

	nodeStatus := &v1alpha1.RouterNodeConfigurationStatus{
		ObjectMeta: metav1.ObjectMeta{Name: r.MyNode, Namespace: r.MyNamespace},
	}
	_, err := ctrlutil.CreateOrUpdate(ctx, r.Client, nodeStatus, func() error {
		return ctrlutil.SetOwnerReference(node, nodeStatus, r.Scheme)
	})
	if err != nil {
		return fmt.Errorf("failed to create or update node status: %w", err)
	}

	return nil
}
