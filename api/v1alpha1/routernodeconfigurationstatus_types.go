// SPDX-License-Identifier:Apache-2.0

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=routernodeconfigurationstatuses
// +kubebuilder:resource:scope=Namespaced
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`,description=Ready
// +kubebuilder:printcolumn:name="Degraded",type=string,JSONPath=`.status.conditions[?(@.type=="Degraded")].status`,description=Degraded
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// RouterNodeConfigurationStatus describes a node router state.
type RouterNodeConfigurationStatus struct {
	metav1.TypeMeta   `json:",inline"`            //nolint:kubeapilinter // suggested godoc is not needed
	metav1.ObjectMeta `json:"metadata,omitempty"` //nolint:kubeapilinter // suggested godoc is not needed

	// status node router configuration status.
	// +optional
	Status *RouterNodeConfigurationStatusStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

type RouterNodeConfigurationStatusList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`

	Items []RouterNodeConfigurationStatus `json:"items"`
}

const (
	ConditionTypeReady              = "Ready"
	ConditionTypeDegraded           = "Degraded"
	ConditionReasonConfigSuccessful = "ConfigurationSuccessful"
	ConditionReasonConfigFailed     = "ConfigurationFailed"
	ConditionReasonUnderlayFailed   = "UnderlayFailed"
)

type RouterNodeConfigurationStatusStatus struct {
	// failedResources list of failed configuration resources on the node.
	// +listType=atomic
	// +optional
	FailedResources []FailedResource `json:"failedResources,omitempty"`

	// conditions list of conditions.
	// +listType=map
	// +listMapKey=type
	// +patchStrategy=merge
	// +patchMergeKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"` // nolint:kubeapilinter // suggested additional tags are not needed
}
