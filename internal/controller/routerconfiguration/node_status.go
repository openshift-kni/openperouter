// SPDX-License-Identifier:Apache-2.0

package routerconfiguration

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"k8s.io/apimachinery/pkg/api/equality"
	k8serr "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"

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

	newStatus := updateStatus(nodeStatus.Status)

	if equality.Semantic.DeepEqual(nodeStatus.Status, newStatus) {
		return nil
	}

	newNodeStatus := nodeStatus.DeepCopy()
	newNodeStatus.Status = newStatus

	if err := r.Status().Patch(ctx, newNodeStatus, client.MergeFrom(nodeStatus)); err != nil {
		return fmt.Errorf("failed to patch status: %w", err)
	}

	r.Logger.Info("successfully updated node status resource",
		"node", r.MyNode, "namespace", r.MyNamespace, "status", newNodeStatus.Status)

	return nil
}

func updateStatus(status *v1alpha1.RouterNodeConfigurationStatusStatus) *v1alpha1.RouterNodeConfigurationStatusStatus {
	updated := status.DeepCopy()
	if updated == nil {
		updated = &v1alpha1.RouterNodeConfigurationStatusStatus{}
	}

	desiredConditions := newConditions()
	for _, desiredCondition := range desiredConditions {
		// SetStatusCondition update lastTransitionTime if unset or differs from desired condition.
		meta.SetStatusCondition(&updated.Conditions, desiredCondition)
	}

	return updated
}

// newConditions return default conditions.
// The conditions lastTransitionTime is unset.
// TODO: create conditions according to status.FailedResources.
func newConditions() []metav1.Condition {
	ready := metav1.Condition{
		Type:    v1alpha1.ConditionTypeReady,
		Status:  metav1.ConditionUnknown,
		Reason:  "Unknown",
		Message: "Unknown status",
	}
	degraded := metav1.Condition{
		Type:    v1alpha1.ConditionTypeDegraded,
		Status:  metav1.ConditionUnknown,
		Reason:  "Unknown",
		Message: "Unknown status",
	}

	return []metav1.Condition{ready, degraded}
}
