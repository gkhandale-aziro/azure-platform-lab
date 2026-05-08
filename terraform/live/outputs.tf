output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "vnet_name" {
  value = module.network.vnet_name
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "acr_name" {
  description = "ACR name."
  value       = module.acr.name
}

output "acr_login_server" {
  description = "ACR login server FQDN."
  value       = module.acr.login_server
}

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.name
}

output "aks_cluster_id" {
  description = "AKS cluster resource ID."
  value       = module.aks.id
}

output "aks_node_resource_group" {
  description = "AKS-managed RG holding nodes/LBs/disks (separate from the platform RG)."
  value       = module.aks.node_resource_group
}

output "kubeconfig_command" {
  description = "Run this to populate ~/.kube/config for kubectl access."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.name} --overwrite-existing"
}
