output "vnet_id" {
  description = "VNet resource ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "VNet name."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet IDs keyed by purpose (aks, apps, mgmt)."
  value = {
    aks  = azurerm_subnet.aks.id
    apps = azurerm_subnet.apps.id
    mgmt = azurerm_subnet.mgmt.id
  }
}

output "nsg_ids" {
  description = "Map of NSG IDs keyed by subnet."
  value = {
    aks  = azurerm_network_security_group.aks.id
    apps = azurerm_network_security_group.apps.id
    mgmt = azurerm_network_security_group.mgmt.id
  }
}
