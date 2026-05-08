variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
  default     = "gskplat"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.name_prefix))
    error_message = "name_prefix must be 3-10 lowercase alphanumeric characters."
  }
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "eastus2"
}

variable "owner" {
  type        = string
  description = "Owner tag value (email or name)."
}

variable "vnet_cidr" {
  type        = string
  description = "VNet CIDR."
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  type = object({
    aks  = string
    apps = string
    mgmt = string
  })
  default = {
    aks  = "10.0.1.0/24"
    apps = "10.0.2.0/24"
    mgmt = "10.0.3.0/27"
  }
}

variable "admin_ip_cidr" {
  type        = string
  description = "Your home/office public IP in CIDR (1.2.3.4/32). Used for AKS API allowlist later and SSH on mgmt subnet."

  validation {
    condition     = can(cidrnetmask(var.admin_ip_cidr))
    error_message = "admin_ip_cidr must be a valid CIDR (e.g. 1.2.3.4/32)."
  }
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Retention in days for the shared Log Analytics workspace."
  default     = 30
}

variable "acr_sku" {
  type        = string
  description = "ACR SKU. Basic for lab; Standard/Premium add features we don't use here."
  default     = "Basic"
}

variable "aks_node_count" {
  type        = number
  description = "AKS default node pool size. Single-node lab default; bump to 2 if you have vCPU headroom and want HA scheduling."
  default     = 1
}

variable "aks_vm_size" {
  type        = string
  description = "AKS node VM size. Standard_B2s is blocked by subscription SKU policy in this trial; Standard_D2s_v3 is the cheapest allowed equivalent (2 vCPU / 8 GB)."
  default     = "Standard_D2s_v3"
}

variable "kubernetes_version" {
  type        = string
  description = "AKS Kubernetes version. null = AKS picks latest stable available in the region."
  default     = null
}
