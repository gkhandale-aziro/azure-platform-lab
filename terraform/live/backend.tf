terraform {
  # Partial backend config — values supplied at `terraform init` time:
  #
  #   terraform init \
  #     -backend-config="resource_group_name=<from bootstrap output>" \
  #     -backend-config="storage_account_name=<from bootstrap output>" \
  #     -backend-config="container_name=tfstate" \
  #     -backend-config="key=live.terraform.tfstate"
  #
  # The exact command is printed by `terraform output backend_init_command_live`
  # in the bootstrap directory after apply.
  backend "azurerm" {}
}
