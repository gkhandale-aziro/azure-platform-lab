output "tfstate_resource_group_name" {
  description = "Resource group holding the Terraform state Storage Account."
  value       = azurerm_resource_group.tfstate.name
}

output "tfstate_storage_account_name" {
  description = "Storage Account name holding tfstate. Globally unique."
  value       = azurerm_storage_account.tfstate.name
}

output "tfstate_container_name" {
  description = "Blob container holding tfstate files."
  value       = azurerm_storage_container.tfstate.name
}

output "backend_init_command_live" {
  description = "Copy-paste command to initialize the live config with the remote backend."
  value = format(
    "terraform init -backend-config=\"resource_group_name=%s\" -backend-config=\"storage_account_name=%s\" -backend-config=\"container_name=%s\" -backend-config=\"key=live.terraform.tfstate\"",
    azurerm_resource_group.tfstate.name,
    azurerm_storage_account.tfstate.name,
    azurerm_storage_container.tfstate.name,
  )
}
