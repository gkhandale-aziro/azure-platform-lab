variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "environment" {
  type        = string
  description = "Environment tag (e.g. shared, platform). Cluster is shared by dev/prod namespaces."
  default     = "shared"
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create network resources in."
}

variable "vnet_cidr" {
  type        = string
  description = "VNet CIDR block."
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  type = object({
    aks  = string
    apps = string
    mgmt = string
  })
  description = "Subnet CIDRs. aks holds AKS nodes, apps for internal LB / private endpoints, mgmt for jumpbox."
  default = {
    aks  = "10.0.1.0/24"
    apps = "10.0.2.0/24"
    mgmt = "10.0.3.0/27"
  }
}

variable "admin_ip_cidr" {
  type        = string
  description = "Admin's home/office public IP in CIDR (e.g. 1.2.3.4/32). Allowed for SSH on mgmt subnet."

  validation {
    condition     = can(cidrnetmask(var.admin_ip_cidr))
    error_message = "admin_ip_cidr must be a valid CIDR (e.g. 1.2.3.4/32)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all network resources."
  default     = {}
}
