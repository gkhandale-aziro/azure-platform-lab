locals {
  module_tags  = merge(var.tags, { Component = "aks" })
  cluster_name = "${var.name_prefix}-aks-${var.environment}"
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version

  # Free SKU control plane: no SLA, suitable for a lab. Standard adds a 99.95% uptime SLA at ~$0.10/hr.
  sku_tier = "Free"

  # Azure auto-enables OIDC issuer on creation and refuses to disable it (OIDCIssuerFeatureCannotBeDisabled).
  # Set explicitly so Terraform's desired state matches reality.
  oidc_issuer_enabled = true

  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.vm_size
    vnet_subnet_id      = var.subnet_id
    type                = "VirtualMachineScaleSets"
    os_disk_type        = "Managed"
    enable_auto_scaling = false

    # Mirror Azure's auto-applied defaults so plans stay clean (otherwise perpetual diff).
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    pod_cidr          = var.pod_cidr
  }

  api_server_access_profile {
    authorized_ip_ranges = [var.admin_ip_cidr]
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  tags = local.module_tags
}
