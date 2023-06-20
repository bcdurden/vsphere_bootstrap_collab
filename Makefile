SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl helm kubectx kubecm terraform
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
TERRAFORM_DIR := ${WORKING_DIR}/terraform
CLUSTER_CONFIG_DIR := ${WORKING_DIR}/cluster_config
WORKLOAD_DIR := ${WORKING_DIR}/workloads

BASE_URL=myurl.lol
CERT_MANAGER_VERSION=1.9.2
RANCHER_VERSION=2.7.1

# Carbide info (only if using carbide)
CARBIDE_TOKEN_FILE=/Volumes/my_volume/keys/carbide.yaml
CARBIDE_REGISTRY := rgcrprod.azurecr.us
CARBIDE_USER := $(shell yq e .token_id ${CARBIDE_TOKEN_FILE})
CARBIDE_PASSWORD:= $(shell yq e .token_password ${CARBIDE_TOKEN_FILE})
CARBIDE_LICENSE := $(shell yq e .license ${CARBIDE_TOKEN_FILE})
STIGATRON_UI_VERSION := 0.1.21

# vsphere details
VSPHERE_CRED_FILE=/Volumes/my_volume/keys/vsphere_creds.yaml
VSPHERE_USERNAME := $(shell yq e .vsphere_username ${VSPHERE_CRED_FILE})
VSPHERE_PASSWORD := $(shell yq e .vsphere_password ${VSPHERE_CRED_FILE})
VSPHERE_URL=vcsa.${BASE_URL}
VSPHERE_DC_NAME=Datacenter
VSPHERE_CLUSTER_NAME=Cluster
VSPHERE_DS_NAME=datastore1
VSPHERE_NETWORK_NAME=rgs-network

# aws details
AWS_CRED_FILE=/Volumes/my_volume/keys/aws_creds.yaml
AWS_ACCESS_KEY := $(shell yq e .aws_access_key_id ${AWS_CRED_FILE})
AWS_SECRET_KEY := $(shell yq e .aws_secret_access_key ${AWS_CRED_FILE})
AWS_REGION=us-east-2

# tailscale
TS_TOKEN_FILE=/Volumes/my_volume/keys/tailscale_token.yaml
TS_KEY := $(shell yq e .tailscale_token ${TS_TOKEN_FILE})

# RKE2 / Local cluster details
RKE2_CP_CPU_COUNT=4
RKE2_CP_MEMORY_SIZE_MB=8192
RKE2_WORKER_CPU_COUNT=4
RKE2_WORKER_MEMORY_SIZE_MB=8192
LOCAL_CLUSTER_NAME=rke2
RKE2_VIP=10.1.1.4
RKE2_VIP_INTERFACE=ens192 # bionic/jammy in vsphere default
RKE2_IMAGE_NAME=jammy-server-cloudimg-amd64
JUMPBOX_IMAGE_NAME=jammy-server-cloudimg-amd64
DOWNSTREAM_CLUSTER_NAME=
CONTENT_LIBRARY_NAME=cl
VSPHERE_ESXI_HOSTS=[\"10.0.0.12\"]

# Rancher details
RANCHER_URL=rancher.${BASE_URL}
RKE2_WORKER_COUNT=3
RANDOM_PASSWORD=$(call randompassword)

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))

rancher: check-tools
	$(call colorecho,"Deploying Rancher to "$(VSPHERE_URL), 6)
	@kubecm delete $(LOCAL_CLUSTER_NAME) || true
	$(call colorecho,"====> Terraforming RKE2 + Rancher", 5)
	@$(MAKE) _terraform COMPONENT=rancher OPTS="-var 'esxi_hosts=$(VSPHERE_ESXI_HOSTS)'" VARS="TF_VAR_vsphere_user=$(VSPHERE_USERNAME) TF_VAR_vsphere_password=$(VSPHERE_PASSWORD) TF_VAR_vsphere_server=$(VSPHERE_URL) TF_VAR_datacenter_name=$(VSPHERE_DC_NAME) TF_VAR_cluster_name=$(VSPHERE_CLUSTER_NAME) TF_VAR_datastore_name=$(VSPHERE_DS_NAME) TF_VAR_network_name="$(VSPHERE_NETWORK_NAME)" TF_VAR_cp_cpu_count=$(RKE2_CP_CPU_COUNT) TF_VAR_cp_memory_size_mb=$(RKE2_CP_MEMORY_SIZE_MB) TF_VAR_worker_count=$(RKE2_WORKER_COUNT) TF_VAR_worker_cpu_count=$(RKE2_WORKER_CPU_COUNT) TF_VAR_worker_memory_size_mb=$(RKE2_WORKER_MEMORY_SIZE_MB) TF_VAR_node_prefix=rke2-ranchermcm TF_VAR_content_library_name=$(CONTENT_LIBRARY_NAME) TF_VAR_rke2_vip=$(RKE2_VIP) TF_VAR_rke2_vip_interface=$(RKE2_VIP_INTERFACE) TF_VAR_rke2_image_name=$(RKE2_IMAGE_NAME) TF_VAR_carbide_username='$(CARBIDE_USER)' TF_VAR_carbide_password='$(CARBIDE_PASSWORD)' TF_VAR_registry_url='$(CARBIDE_REGISTRY)'"
	@cp ${TERRAFORM_DIR}/rancher/kube_config.yaml /tmp/$(LOCAL_CLUSTER_NAME).yaml && kubecm add -c -f /tmp/$(LOCAL_CLUSTER_NAME).yaml && rm /tmp/$(LOCAL_CLUSTER_NAME).yaml
	@kubectx $(LOCAL_CLUSTER_NAME)
	@helm upgrade --install cert-manager -n cert-manager --create-namespace --set installCRDs=true --set image.repository=$(CARBIDE_REGISTRY)/jetstack/cert-manager-controller --set webhook.image.repository=$(CARBIDE_REGISTRY)/jetstack/cert-manager-webhook --set cainjector.image.repository=$(CARBIDE_REGISTRY)/jetstack/cert-manager-cainjector --set startupapicheck.image.repository=$(CARBIDE_REGISTRY)/jetstack/cert-manager-ctl --set securityContext.runAsNonRoot=true https://charts.jetstack.io/charts/cert-manager-v$(CERT_MANAGER_VERSION).tgz
	@helm upgrade --install rancher -n cattle-system --create-namespace --set hostname=$(RANCHER_URL) --set replicas=$(RKE2_WORKER_COUNT) --set bootstrapPassword=admin --set rancherImage=$(CARBIDE_REGISTRY)/rancher/rancher --set "carbide.whitelabel.image=$(CARBIDE_REGISTRY)/carbide/carbide-whitelabel" --set systemDefaultRegistry=$(CARBIDE_REGISTRY) --version v${RANCHER_VERSION} carbide-charts/rancher
	$(call colorecho,"====> Waiting for Rancher to become available", 5)
	@kubectl rollout status deployment -n cattle-system rancher
	@kubectl create ns fleet-default || true
	$(call colorecho,"====> Creating Carbide registry auth secret", 5)
	@kubectl create secret generic --type kubernetes.io/basic-auth carbide-registry -n fleet-default --from-literal=username=${CARBIDE_USER} --from-literal=password=${CARBIDE_PASSWORD} --dry-run=client -o yaml | kubectl apply -f - 2>&1 | grep -i -v "Warn" | grep -i -v "Deprecat"
	@helm repo add carbide-charts https://rancherfederal.github.io/carbide-charts || true
	@$(MAKE) rancher-bootstrap PASSWORD=${RANDOM_PASSWORD}

rancher-bootstrap:
	$(call colorecho, "====> Bootstrapping Rancher", 5)
	@kubectx $(LOCAL_CLUSTER_NAME)
	@curl -sk https://${RANCHER_URL}/v3/users?action=changepassword -H 'content-type: application/json' -H "Authorization: Bearer $$(curl -sk -X POST https://${RANCHER_URL}/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"admin"}' | jq -r '.token')" -d '{"currentPassword":"admin","newPassword":"'${PASSWORD}'"}'  > /dev/null 2>&1 
	@curl -sk https://${RANCHER_URL}/v3/settings/server-url -H 'content-type: application/json' -H "Authorization: Bearer $$(curl -sk -X POST https://${RANCHER_URL}/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"${PASSWORD}"}' | jq -r '.token')" -X PUT -d '{"name":"server-url","value":"https://${RANCHER_URL}"}'  > /dev/null 2>&1
	@curl -sk https://${RANCHER_URL}/v3/settings/telemetry-opt -X PUT -H 'content-type: application/json' -H 'accept: application/json' -H "Authorization: Bearer $$(curl -sk -X POST https://${RANCHER_URL}/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"${PASSWORD}"}' | jq -r '.token')" -d '{"value":"out"}' > /dev/null 2>&1
	@curl -sk https://${RANCHER_URL}/v1/catalog.cattle.io.clusterrepos -H 'content-type: application/json' -H "Authorization: Bearer $$(curl -sk -X POST https://${RANCHER_URL}/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"${PASSWORD}"}' | jq -r '.token')" -d '{"type":"catalog.cattle.io.clusterrepo","metadata":{"name":"rancher-ui-plugins"},"spec":{"gitBranch":"main","gitRepo":"https://github.com/rancher/ui-plugin-charts"}}' > /dev/null 2>&1
	@curl -sk https://${RANCHER_URL}/v1/catalog.cattle.io.clusterrepos/rancher-charts?action=install -H 'content-type: application/json' -H "Authorization: Bearer $$(curl -sk -X POST https://${RANCHER_URL}/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"${PASSWORD}"}' | jq -r '.token')" -d '{"charts":[{"chartName":"ui-plugin-operator-crd","version":"101.0.0+up0.1.0","releaseName":"ui-plugin-operator-crd","annotations":{"catalog.cattle.io/ui-source-repo-type":"cluster","catalog.cattle.io/ui-source-repo":"rancher-charts"}}],"wait":true,"namespace":"cattle-ui-plugin-system"}' > /dev/null 2>&1
	@curl -sk https://${RANCHER_URL}/v1/catalog.cattle.io.clusterrepos/rancher-charts?action=install -H 'content-type: application/json' -H "Authorization: Bearer $$(curl -sk -X POST https://${RANCHER_URL}/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"${PASSWORD}"}' | jq -r '.token')" -d '{"charts":[{"chartName":"ui-plugin-operator","version":"101.0.0+up0.1.0","releaseName":"ui-plugin-operator","annotations":{"catalog.cattle.io/ui-source-repo-type":"cluster","catalog.cattle.io/ui-source-repo":"rancher-charts"}}],"wait":true,"namespace":"cattle-ui-plugin-system"}' > /dev/null 2>&1
	$(call colorecho, "Rancher password (Save this somewhere): ${PASSWORD}", 9)
	@sleep 5
	$(call colorecho,"====> Installing UI Plugin Operator", 5)
	@until [ $$(helm status ui-plugin-operator -n cattle-ui-plugin-system -o yaml | yq e '.info.status' | grep deployed | wc -l) = 1 ]; do sleep 2;	echo -e -n ".";	done
	@helm upgrade --install -n carbide-stigatron-system --no-hooks --create-namespace stigatron-ui --set global.cattle.systemDefaultRegistry=$(CARBIDE_REGISTRY) carbide-charts/stigatron-ui --version 0.1.21
	@$(MAKE) workloads

workloads: check-tools
	$(call colorecho, "====> Creating Downstream clusters", 5)
	@kubectx $(LOCAL_CLUSTER_NAME)
	$(call colorecho, "Waiting on Fleet agent", 6)
	@until [ $$(kubectl get deploy fleet-agent -n cattle-fleet-local-system -o yaml | yq e '.status.availableReplicas' | grep 1 | wc -l) = 1 ]; do sleep 2; echo -e -n "."; done
	@ytt -f ${CLUSTER_CONFIG_DIR}/ytt_overlay -f ${CLUSTER_CONFIG_DIR}/vsphere_cred.yaml -v vsphere_username=$(VSPHERE_USERNAME) -v vsphere_password=$(VSPHERE_PASSWORD) -v vsphere_url=$(VSPHERE_URL) | kubectl apply -f -
	@ytt -f ${CLUSTER_CONFIG_DIR}/ytt_overlay -f ${CLUSTER_CONFIG_DIR}/aws_cred.yaml -v aws_access_key=$(AWS_ACCESS_KEY) -v aws_region=$(AWS_REGION) -v aws_secret_key=$(AWS_SECRET_KEY) | kubectl apply -f -
	@helm upgrade --install -f ${CLUSTER_CONFIG_DIR}/shared/values.yaml shared-cluster cluster_template/
	@ytt -f $(WORKLOAD_DIR) | kapp deploy -a workloads -f - -y

workloads-aws: check-tools
	$(call colorecho, "====> Creating AWS clusters", 5)
	@cat ${CLUSTER_CONFIG_DIR}/aws/values.yaml | TS_KEY=$(TS_KEY) envsubst | helm upgrade --install -f - aws-cluster cluster_template/

rancher-delete: rancher-destroy
rancher-destroy: check-tools
	$(call colorecho, "====> Destroying RKE2 + Rancher", 5)
	@$(MAKE) _terraform-destroy OPTS="-var 'esxi_hosts=$(VSPHERE_ESXI_HOSTS)'" COMPONENT=rancher VARS="TF_VAR_vsphere_user=$(VSPHERE_USERNAME) TF_VAR_vsphere_password=$(VSPHERE_PASSWORD) TF_VAR_vsphere_server=$(VSPHERE_URL) TF_VAR_datacenter_name=$(VSPHERE_DC_NAME) TF_VAR_cluster_name=$(VSPHERE_CLUSTER_NAME) TF_VAR_datastore_name=$(VSPHERE_DS_NAME) TF_VAR_network_name='$(VSPHERE_NETWORK_NAME)' TF_VAR_cp_cpu_count=$(RKE2_CP_CPU_COUNT) TF_VAR_cp_memory_size_mb=$(RKE2_CP_MEMORY_SIZE_MB) TF_VAR_worker_count=$(RKE2_WORKER_COUNT) TF_VAR_worker_cpu_count=$(RKE2_WORKER_CPU_COUNT) TF_VAR_worker_memory_size_mb=$(RKE2_WORKER_MEMORY_SIZE_MB) TF_VAR_node_prefix=rke2-ranchermcm TF_VAR_content_library_name=$(CONTENT_LIBRARY_NAME) TF_VAR_rke2_vip=$(RKE2_VIP) TF_VAR_rke2_vip_interface=$(RKE2_VIP_INTERFACE) TF_VAR_rke2_image_name=$(RKE2_IMAGE_NAME) TF_VAR_carbide_username='$(CARBIDE_USER)' TF_VAR_carbide_password='$(CARBIDE_PASSWORD)' TF_VAR_registry_url='$(CARBIDE_REGISTRY)'"
	@kubecm delete $(LOCAL_CLUSTER_NAME) || true

jumpbox: check-tools
	$(call colorecho, "====> Terraforming Jumpbox", 5)
	@$(MAKE) _terraform COMPONENT=jumpbox OPTS="-var 'esxi_hosts=$(VSPHERE_ESXI_HOSTS)'" VARS="TF_VAR_vsphere_user=$(VSPHERE_USERNAME) TF_VAR_vsphere_password='$(VSPHERE_PASSWORD)' TF_VAR_vsphere_server=$(VSPHERE_URL) TF_VAR_datacenter_name=$(VSPHERE_DC_NAME) TF_VAR_cluster_name=$(VSPHERE_CLUSTER_NAME) TF_VAR_datastore_name=$(VSPHERE_DS_NAME) TF_VAR_network_name='$(VSPHERE_NETWORK_NAME)' TF_VAR_content_library_name='$(CONTENT_LIBRARY_NAME)' TF_VAR_vm_image_name=$(JUMPBOX_IMAGE_NAME)"
jumpbox-delete: rancher-destroy
jumpbox-destroy: check-tools
	$(call colorecho, "====> Destroying Jumpbox", 5)
	@$(MAKE) _terraform-destroy COMPONENT=jumpbox OPTS="-var 'esxi_hosts=$(VSPHERE_ESXI_HOSTS)'" VARS='TF_VAR_vsphere_user=$(VSPHERE_USERNAME) TF_VAR_vsphere_password=$(VSPHERE_PASSWORD) TF_VAR_vsphere_server=$(VSPHERE_URL) TF_VAR_datacenter_name=$(VSPHERE_DC_NAME) TF_VAR_cluster_name=$(VSPHERE_CLUSTER_NAME) TF_VAR_datastore_name=$(VSPHERE_DS_NAME) TF_VAR_network_name="$(VSPHERE_NETWORK_NAME)" TF_VAR_content_library_name="$(CONTENT_LIBRARY_NAME)" TF_VAR_vm_image_name=$(JUMPBOX_IMAGE_NAME)'

# downstreamcluster: check-tools
# 	$(call colorecho, "====> Terraforming RKE2", 5)
# 	@kubecm delete $(DOWNSTREAM_CLUSTER_NAME) || true
# 	@$(MAKE) _terraform COMPONENT=cluster OPTS="-var 'esxi_hosts=$(VSPHERE_ESXI_HOSTS)'" VARS='TF_VAR_vsphere_user=$(VSPHERE_USERNAME) TF_VAR_vsphere_password=$'(VSPHERE_PASSWORD)' TF_VAR_vsphere_server=$(VSPHERE_URL) TF_VAR_datacenter_name=$(VSPHERE_DC_NAME) TF_VAR_cluster_name=$(VSPHERE_CLUSTER_NAME) TF_VAR_datastore_name=$(VSPHERE_DS_NAME) TF_VAR_network_name="$(VSPHERE_NETWORK_NAME)" TF_VAR_cp_cpu_count=$(RKE2_CP_CPU_COUNT) TF_VAR_cp_memory_size_mb=$(RKE2_CP_MEMORY_SIZE_MB) TF_VAR_worker_count=$(RKE2_WORKER_COUNT) TF_VAR_worker_cpu_count=$(RKE2_WORKER_CPU_COUNT) TF_VAR_worker_memory_size_mb=$(RKE2_WORKER_MEMORY_SIZE_MB) TF_VAR_node_prefix=rke2-$(DOWNSTREAM_CLUSTER_NAME) TF_VAR_content_library_name=$(CONTENT_LIBRARY_NAME) TF_VAR_rke2_vip=$(RKE2_VIP) TF_VAR_rke2_vip_interface=$(RKE2_VIP_INTERFACE) TF_VAR_rke2_image_name=$(RKE2_IMAGE_NAME)'
# 	@cp ${TERRAFORM_DIR}/cluster/kube_config.yaml /tmp/$(DOWNSTREAM_CLUSTER_NAME).yaml && kubecm add -c -f /tmp/$(DOWNSTREAM_CLUSTER_NAME).yaml && rm /tmp/$(DOWNSTREAM_CLUSTER_NAME).yaml
# 	@kubectx $(DOWNSTREAM_CLUSTER_NAME)

# downstreamcluster-delete: rancher-destroy
# downstreamcluster-destroy: check-tools
# 	$(call colorecho, "====> Destroying RKE2", 5)
# 	@$(MAKE) _terraform-destroy COMPONENT=cluster VARS='TF_VAR_vsphere_user=$(VSPHERE_USERNAME) TF_VAR_vsphere_password=$'(VSPHERE_PASSWORD)' TF_VAR_vsphere_server=$(VSPHERE_URL) TF_VAR_datacenter_name=$(VSPHERE_DC_NAME) TF_VAR_cluster_name=$(VSPHERE_CLUSTER_NAME) TF_VAR_datastore_name=$(VSPHERE_DS_NAME) TF_VAR_network_name="$(VSPHERE_NETWORK_NAME)" TF_VAR_cp_cpu_count=$(RKE2_CP_CPU_COUNT) TF_VAR_cp_memory_size_mb=$(RKE2_CP_MEMORY_SIZE_MB) TF_VAR_worker_count=$(RKE2_WORKER_COUNT) TF_VAR_worker_cpu_count=$(RKE2_WORKER_CPU_COUNT) TF_VAR_worker_memory_size_mb=$(RKE2_WORKER_MEMORY_SIZE_MB) TF_VAR_node_prefix=rke2-$(DOWNSTREAM_CLUSTER_NAME) TF_VAR_content_library_name=$(CONTENT_LIBRARY_NAME) TF_VAR_rke2_vip=$(RKE2_VIP) TF_VAR_rke2_vip_interface=$(RKE2_VIP_INTERFACE) TF_VAR_rke2_image_name=$(RKE2_IMAGE_NAME)'
# 	@kubecm delete $(DOWNSTREAM_CLUSTER_NAME) || true

carbide-license: check-tools
	$(call colorecho, "===>Creating Carbide License", 5)
	$(call colorecho, "Copy-paste this into your target cluster shell:",9)
	$(call colorecho, "kubectl create namespace carbide-stigatron-system; kubectl create secret generic stigatron-license -n carbide-stigatron-system --from-literal=license=${CARBIDE_LICENSE} --dry-run=client -o yaml | kubectl apply -f -", 3)

# terraform sub-targets (don't use directly)
_terraform: check-tools
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) init
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) apply $(OPTS)
_terraform-init: check-tools
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) init
_terraform-apply: check-tools
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) apply $(OPTS)
_terraform-value: check-tools
	@terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) output -json | jq -r '$(FIELD)'
_terraform-destroy: check-tools
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) destroy $(OPTS) 


define colorecho
@tput setaf $2
@echo $1
@tput sgr0
endef
define randompassword
${shell head /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 13}
endef