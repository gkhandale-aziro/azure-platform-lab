output "id" {
  description = "AKS cluster resource ID."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity. Grant this AcrPull on ACR so the cluster can pull images."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "node_resource_group" {
  description = "RG that AKS auto-creates for nodes/LBs/disks (separate from the platform RG)."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}
