locals {
  environment = "shared" # cluster shared by dev and prod namespaces

  common_tags = {
    Environment = local.environment
    Project     = "azure-platform-lab"
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
}

# Identity Terraform is currently authenticated as. Used to grant the SP
# Cluster Admin on AKS so kubectl works without device-code re-auth.
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-rg-platform"
  location = var.location
  tags     = local.common_tags
}

# Shared Log Analytics workspace — AKS, ACR, and any future diagnostic settings ship here.
# 5 GB/month free ingestion; lab usage will stay well under this.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-law-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

module "network" {
  source = "../modules/network"

  name_prefix         = var.name_prefix
  environment         = local.environment
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  vnet_cidr     = var.vnet_cidr
  subnet_cidrs  = var.subnet_cidrs
  admin_ip_cidr = var.admin_ip_cidr

  tags = local.common_tags
}

module "acr" {
  source = "../modules/acr"

  name_prefix         = var.name_prefix
  environment         = local.environment
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.acr_sku

  tags = local.common_tags
}

module "aks" {
  source = "../modules/aks"

  name_prefix         = var.name_prefix
  environment         = local.environment
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  subnet_id                  = module.network.subnet_ids.aks
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  admin_ip_cidr              = var.admin_ip_cidr

  node_count         = var.aks_node_count
  vm_size            = var.aks_vm_size
  kubernetes_version = var.kubernetes_version

  tags = local.common_tags
}

# AKS kubelet identity needs AcrPull so the cluster can pull images we push to ACR.
resource "azurerm_role_assignment" "aks_acrpull" {
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

# Terraform's SP gets cluster admin on AKS so kubectl works using SP creds (not device code).
resource "azurerm_role_assignment" "tf_sp_cluster_admin" {
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Coming in iteration 3 (Kubernetes manifests, not Terraform):
#   - Istio install (kubernetes/istio)
#   - ArgoCD install (kubernetes/argocd) — drift-detection mode
#   - Jenkins install (kubernetes/jenkins) — runs the CI pipeline
#
# Coming in iteration 4 (the 3-tier app):
#   - kubernetes/apps/three-tier/{frontend,backend,database}/   Helm charts
#   - kubernetes/apps/three-tier/values-dev.yaml
#   - kubernetes/apps/three-tier/values-prod.yaml
# ---------------------------------------------------------------------------
