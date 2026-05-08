locals {
  module_tags = merge(var.tags, { Component = "acr" })
}

# ACR names are globally unique across Azure, lowercase alphanumeric, 5-50 chars.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_container_registry" "this" {
  name                = "${var.name_prefix}acr${random_string.suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  # AAD/RBAC auth only (AcrPush, AcrPull). Admin user is a shared-secret backdoor we don't want.
  admin_enabled = false

  tags = local.module_tags
}
