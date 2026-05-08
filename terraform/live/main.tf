locals {
  environment = "shared" # cluster shared by dev and prod namespaces

  common_tags = {
    Environment = local.environment
    Project     = "azure-platform-lab"
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
}

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

# ---------------------------------------------------------------------------
# Coming in iteration 2:
#   module "acr"      { ... }   # Azure Container Registry (Basic SKU)
#   module "aks"      { ... }   # AKS cluster, B2s nodes, kubenet, OMS addon → LAW
#
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
