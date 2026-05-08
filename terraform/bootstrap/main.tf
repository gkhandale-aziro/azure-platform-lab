locals {
  common_tags = merge(var.extra_tags, {
    Environment = "shared"
    Project     = "azure-platform-lab"
    Owner       = var.owner
    ManagedBy   = "terraform"
    Component   = "bootstrap"
  })
}

# Storage Account names must be globally unique, 3-24 chars, lowercase alphanumeric.
resource "random_string" "sa_suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_resource_group" "tfstate" {
  name     = "${var.name_prefix}-rg-tfstate"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "${var.name_prefix}tfstate${random_string.sa_suffix.result}"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version               = "TLS1_2"
  shared_access_key_enabled     = true # required for the azurerm Terraform backend
  public_network_access_enabled = true # lab convenience; lock down with network_rules in prod

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
