variable "name_prefix" {
  type        = string
  description = "Resource name prefix (lowercase alphanumeric; used in the globally-unique ACR name)."
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
  description = "Resource group to create the ACR in."
}

variable "sku" {
  type        = string
  description = "ACR SKU. Basic is sufficient for a lab; Standard/Premium add geo-replication and private endpoints."
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard, or Premium."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the registry."
  default     = {}
}
