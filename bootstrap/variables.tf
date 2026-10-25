variable "subscription_id" {
  description = "Azure subscription to deploy into (az account show --query id -o tsv)."
  type        = string
}

variable "location" {
  description = "Region of the state storage account (same as the cluster)."
  type        = string
  default     = "swedencentral"
}

variable "env" {
  description = "Environment name, used in the state key."
  type        = string
  default     = "dev"
}

variable "github_repo" {
  description = "owner/name of the repository whose workflows may log in."
  type        = string
  default     = "anddr13/voting-infra-azure"
}
