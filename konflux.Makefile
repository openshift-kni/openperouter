PROJECT_DIR := $(shell dirname $(abspath $(firstword $(MAKEFILE_LIST))))

# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 4.20.0

# OPERATOR_SDK_VERSION defines the operator-sdk version to download from GitHub releases.
OPERATOR_SDK_VERSION ?= v1.41.1

# YQ_VERSION defines the yq version to download from GitHub releases.
YQ_VERSION ?= v4.45.4

# OPM_VERSION defines the opm version to download from GitHub releases.
OPM_VERSION ?= v1.52.0

## Tool Binaries

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk
OPM ?= $(LOCALBIN)/opm
YQ ?= $(LOCALBIN)/yq

.PHONY: yq
yq: ## Download yq locally if necessary
	@echo "Downloading yq..."
	$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/download download-yq DOWNLOAD_INSTALL_DIR=$(PROJECT_DIR)/bin
	$(YQ) --version
	@cp $(YQ) /usr/bin/yq
	@echo "Yq downloaded successfully."

.PHONY: yq-sort-and-format
yq-sort-and-format: yq ## Sort keys/reformat all yaml files 
	@echo "Sorting keys and reformatting YAML files..."
	@find . -name "*.yaml" -o -name "*.yml" | grep -v -E "(telco5g-konflux/|target/|vendor/|bin/|\.git/)" | while read file; do \
		echo "Processing $$file..."; \
		$(YQ) -i '.. |= sort_keys(.)' "$$file"; \
	done
	@echo "YAML sorting and formatting completed successfully."

operator-sdk: ## Download operator-sdk locally if necessary
	@$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/download download-operator-sdk \
		DOWNLOAD_INSTALL_DIR=$(PROJECT_DIR)/bin \
		DOWNLOAD_OPERATOR_SDK_VERSION=$(OPERATOR_SDK_VERSION)
	@echo "Operator sdk downloaded successfully."

.PHONY: opm
opm: ## Download opm locally if necessary
	@$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/download download-opm \
		DOWNLOAD_INSTALL_DIR=$(PROJECT_DIR)/bin \
		DOWNLOAD_OPM_VERSION=$(OPM_VERSION)
	$(OPM) version
	@cp $(OPM) /usr/bin/opm
	@echo "Opm downloaded successfully."

##@ Konflux
PACKAGE_NAME_KONFLUX = openperouter-operator
CATALOG_TEMPLATE_KONFLUX = .konflux/catalog/catalog-template.in.yaml
CATALOG_KONFLUX = .konflux/catalog/$(PACKAGE_NAME_KONFLUX)/catalog.yaml
BUNDLE_NAME_SUFFIX = bundle-4-20
PRODUCTION_BUNDLE_NAME = bundle
PRODUCTION_NAMESPACE = openshift4-dev-preview-beta

# You can use podman or docker as a container engine. Notice that there are some options that might be only valid for one of them.
ENGINE ?= docker

.PHONY: konflux-validate-catalog-template-bundle ## validate the last bundle entry on the catalog template file
konflux-validate-catalog-template-bundle: yq operator-sdk
	$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/catalog konflux-validate-catalog-template-bundle \
		CATALOG_TEMPLATE_KONFLUX=$(PROJECT_DIR)/$(CATALOG_TEMPLATE_KONFLUX) PRODUCTION_NAMESPACE=$(PRODUCTION_NAMESPACE) \
		YQ=$(YQ) \
		OPERATOR_SDK=$(OPERATOR_SDK) \
		ENGINE=$(ENGINE)

.PHONY: konflux-validate-catalog
konflux-validate-catalog: opm ## validate the current catalog file
	$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/catalog konflux-validate-catalog \
		CATALOG_KONFLUX=$(PROJECT_DIR)/$(CATALOG_KONFLUX) PRODUCTION_NAMESPACE=$(PRODUCTION_NAMESPACE) \
		OPM=$(OPM)

.PHONY: konflux-generate-catalog ## generate a quay.io catalog
konflux-generate-catalog: yq opm
	$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/catalog konflux-generate-catalog \
		CATALOG_TEMPLATE_KONFLUX=$(PROJECT_DIR)/$(CATALOG_TEMPLATE_KONFLUX) \
		CATALOG_KONFLUX=$(PROJECT_DIR)/$(CATALOG_KONFLUX) PRODUCTION_NAMESPACE=$(PRODUCTION_NAMESPACE) \
		PACKAGE_NAME_KONFLUX=$(PACKAGE_NAME_KONFLUX) \
		BUNDLE_BUILDS_FILE=$(PROJECT_DIR)/.konflux/catalog/bundle.builds.in.yaml \
		OPM=$(OPM) \
		YQ=$(YQ)
	$(MAKE) konflux-validate-catalog

.PHONY: konflux-generate-catalog-production ## generate a registry.redhat.io catalog
konflux-generate-catalog-production: yq opm
	$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/catalog konflux-generate-catalog-production \
		CATALOG_TEMPLATE_KONFLUX=$(PROJECT_DIR)/$(CATALOG_TEMPLATE_KONFLUX) \
		CATALOG_KONFLUX=$(PROJECT_DIR)/$(CATALOG_KONFLUX) PRODUCTION_NAMESPACE=$(PRODUCTION_NAMESPACE) \
		PACKAGE_NAME_KONFLUX=$(PACKAGE_NAME_KONFLUX) \
		BUNDLE_NAME_SUFFIX=$(BUNDLE_NAME_SUFFIX) \
		PRODUCTION_BUNDLE_NAME=$(PRODUCTION_BUNDLE_NAME) \
		BUNDLE_BUILDS_FILE=$(PROJECT_DIR)/.konflux/catalog/bundle.builds.in.yaml \
		OPM=$(OPM) \
		YQ=$(YQ)
	$(MAKE) konflux-validate-catalog

.PHONY: konflux-filter-unused-redhat-repos
konflux-filter-unused-redhat-repos: ## Filter unused repositories from redhat.repo files in runtime lock folder
	@echo "Filtering unused repositories from runtime lock folder..."
	$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/rpm-lock filter-unused-repos REPO_FILE=$(PROJECT_DIR)/.konflux/lock-runtime/redhat.repo
	@echo "Filtering completed for runtime lock folder."

.PHONY: konflux-update-tekton-task-refs
konflux-update-tekton-task-refs: ## Update task references in Tekton pipeline files
	@echo "Updating task references in Tekton pipeline files..."
	$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/tekton update-task-refs PIPELINE_FILES="$(shell find $(PROJECT_DIR)/.tekton -name '*.yaml' -not -name 'OWNERS' | tr '\n' ' ')"
	@echo "Task references updated successfully."

.PHONY: konflux-compare-catalog
konflux-compare-catalog: ## Compare generated catalog with upstream FBC image
	@echo "Comparing generated catalog with upstream FBC image..."
	$(MAKE) -C $(PROJECT_DIR)/telco5g-konflux/scripts/catalog konflux-compare-catalog \
		CATALOG_KONFLUX=$(PROJECT_DIR)/$(CATALOG_KONFLUX) PRODUCTION_NAMESPACE=$(PRODUCTION_NAMESPACE) \
		PACKAGE_NAME_KONFLUX=$(PACKAGE_NAME_KONFLUX) \
		UPSTREAM_FBC_IMAGE=quay.io/redhat-user-workloads/telco-5g-tenant/$(PACKAGE_NAME_KONFLUX)-fbc-4-20:latest

.PHONY: konflux-all
konflux-catalog-all: konflux-validate-catalog-template-bundle konflux-generate-catalog-production  konflux-compare-catalog ## Run all konflux catalog logic
	@echo "All Konflux targets completed successfully."