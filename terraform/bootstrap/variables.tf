variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names. Lowercase alphanumeric only (used in globally-unique resources like Storage Accounts)."
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

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags merged into common tags."
  default     = {}
}
