variable "monitoring_folder_id" {
  type        = string
  description = "Folder ID where monitoring data is collected"
  default     = ""
}

variable "monitoring_organization_id" {
  type        = string
  description = "Organization ID for quota collection"
  default     = ""
}

variable "monitoring_billing_account_id" {
  type        = string
  description = "Billing Account ID for quota collection"
  default     = ""
}
