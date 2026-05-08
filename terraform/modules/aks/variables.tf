variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "environment" {
  type        = string
  description = "Environment tag (e.g. shared)."
  default     = "shared"
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create the cluster in."
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the AKS node pool. With kubenet, pods are NOT placed on this subnet — only nodes."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics workspace ID for the OMS agent (Container Insights)."
}

variable "admin_ip_cidr" {
  type        = string
  description = "CIDR allowed to reach the public AKS API server."

  validation {
    condition     = can(cidrnetmask(var.admin_ip_cidr))
    error_message = "admin_ip_cidr must be a valid CIDR."
  }
}

variable "node_count" {
  type        = number
  description = "Default node pool size. Free Trial caps B-series at 4 vCPU/region; B2s = 2 vCPU."
  default     = 2
}

variable "vm_size" {
  type        = string
  description = "VM size for the default node pool."
  default     = "Standard_B2s"
}

variable "kubernetes_version" {
  type        = string
  description = "AKS Kubernetes version. null lets AKS choose the latest stable."
  default     = null
}

variable "service_cidr" {
  type        = string
  description = "Cluster service IP range. MUST NOT overlap the VNet CIDR."
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  type        = string
  description = "DNS service IP within service_cidr (typically .10)."
  default     = "172.16.0.10"
}

variable "pod_cidr" {
  type        = string
  description = "Pod IP range for kubenet. MUST NOT overlap the VNet CIDR."
  default     = "10.244.0.0/16"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the cluster."
  default     = {}
}
